package main

/*
#include <stdlib.h>
#include <jni.h>
*/
import "C"

import (
	"bufio"
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
	"unsafe"
)

var (
	tunFile  *os.File
	mu       sync.Mutex
	tunFd    int
	ctx      context.Context
	cancelFn context.CancelFunc
	status   = map[string]interface{}{"state": "DISCONNECTED"}
	// firebase realtime database URL (from firebase_options.dart)
	firebaseDB        = "https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app"
	lastPublishedIP   string
	lastPublishedPort int
	// internal channels for simulated WebRTC/data-channel placeholders
	peerUpdateCh = make(chan struct{}, 1)
)

//export SubmitTunFd
func SubmitTunFd(fd C.int) C.int {
	mu.Lock()
	defer mu.Unlock()
	if int(fd) <= 0 {
		return C.int(-1)
	}
	tunFd = int(fd)
	// keep a dummy os.File to avoid GC closing issues in some cases
	tunFile = os.NewFile(uintptr(fd), "tunfd")
	status["state"] = "TUN_READY"
	return 0
}

//export Java_com_shiva2232_orbitx_VpnBridge_submitTunFd
func Java_com_shiva2232_orbitx_VpnBridge_submitTunFd(env *C.JNIEnv, clazz C.jclass, fd C.jint) C.jint {
	return SubmitTunFd(fd)
}

//export Java_com_shiva2232_orbitx_VpnBridge_startEngine
func Java_com_shiva2232_orbitx_VpnBridge_startEngine(env *C.JNIEnv, clazz C.jclass, cpair C.jstring, crole C.jstring, csecret C.jstring) C.jint {
	pairPtr := C.GetStringUTFChars(env, cpair, nil)
	rolePtr := C.GetStringUTFChars(env, crole, nil)
	secretPtr := C.GetStringUTFChars(env, csecret, nil)
	pair := C.GoString(pairPtr)
	role := C.GoString(rolePtr)
	secret := C.GoString(secretPtr)
	C.ReleaseStringUTFChars(env, cpair, pairPtr)
	C.ReleaseStringUTFChars(env, crole, rolePtr)
	C.ReleaseStringUTFChars(env, csecret, secretPtr)

	cp := C.CString(pair)
	cr := C.CString(role)
	cs := C.CString(secret)
	defer C.free(unsafe.Pointer(cp))
	defer C.free(unsafe.Pointer(cr))
	defer C.free(unsafe.Pointer(cs))
	return StartEngine(cp, cr, cs)
}

//export StartEngine
func StartEngine(cpair *C.char, crole *C.char, csecret *C.char) C.int {
	pair := C.GoString(cpair)
	role := C.GoString(crole)
	_ = C.GoString(csecret)

	mu.Lock()
	if tunFd == 0 {
		mu.Unlock()
		return C.int(-2) // fd missing
	}
	if cancelFn != nil {
		cancelFn()
	}
	ctx, cancelFn = context.WithCancel(context.Background())
	status["state"] = "CONNECTING"
	status["pair"] = pair
	status["role"] = role
	mu.Unlock()

	// kick off engine subroutines: heartbeat, peer listener, and engine loop
	go engineLoop(ctx)

	// start a heartbeat that republishes our endpoint to Firebase (using a placeholder ip/port)
	go heartbeatLoop(ctx, pair, role, "0.0.0.0", 0)

	// start listening for peer updates
	go func() {
		listenPeerEndpoint(pair, oppositeRole(role), nil)
	}()

	// react to peer updates stored into status by listenPeerEndpoint
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case <-peerUpdateCh:
				// extract peer info
				mu.Lock()
				pip, _ := status["peerIp"].(string)
				portVal := status["peerPort"]
				var pport int
				switch v := portVal.(type) {
				case int:
					pport = v
				case float64:
					pport = int(v)
				default:
					pport = 0
				}
				ppriv, _ := status["peerPrivateIp"].(string)
				myPub := lastPublishedIP
				mu.Unlock()

				// prefer private LAN if public IPs match and private candidate exists
				if myPub != "" && pip != "" && myPub == pip && ppriv != "" {
					bridgeWebRTC(ppriv, pport, ppriv)
				} else {
					bridgeWebRTC(pip, pport, ppriv)
				}
			}
		}
	}()

	return 0
}

func engineLoop(ctx context.Context) {
	// simple simulated engine: after 1s -> WAITING_PEER, 2s -> CONNECTED
	updateStatus(map[string]interface{}{"state": "WAITING_PEER"})
	select {
	case <-time.After(2 * time.Second):
		updateStatus(map[string]interface{}{"state": "CONNECTED", "peerIp": "203.0.113.5", "peerPort": 12345, "lastHandshakeMs": time.Now().UnixMilli()})
	case <-ctx.Done():
		updateStatus(map[string]interface{}{"state": "DISCONNECTED"})
		return
	}

	// heartbeat
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			// noop
		case <-ctx.Done():
			updateStatus(map[string]interface{}{"state": "DISCONNECTED"})
			return
		}
	}
}

func setStatus(m map[string]interface{}) {
	mu.Lock()
	for k, v := range m {
		status[k] = v
	}
	mu.Unlock()
}

// writeEndpointToFirebase writes the local published endpoint record for signaling and keepalive.
func writeEndpointToFirebase(hash, role, ip string, port int) error {
	url := fmt.Sprintf("%s/pairings/%s/%s.json", firebaseDB, hash, role)
	privateIP := getLocalPrivateIP()
	payload := map[string]interface{}{
		"ip":        ip,
		"port":      port,
		"privateIp": privateIP,
		"updatedAt": time.Now().UnixMilli(),
		"online":    true,
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPut, url, bytes.NewReader(b))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	return nil
}

// getPublicIP queries a public service to determine this device's public IP.
func getPublicIP() (string, error) {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://api.ipify.org?format=json")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var r struct {
		IP string `json:"ip"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return "", err
	}
	return r.IP, nil
}

// refreshAndPublishEndpoint obtains current public IP and publishes to Firebase only when changed.
func refreshAndPublishEndpoint(hash, role string, port int) error {
	ip, err := getPublicIP()
	if err != nil {
		return err
	}
	mu.Lock()
	if ip == lastPublishedIP && port == lastPublishedPort {
		mu.Unlock()
		return nil
	}
	lastPublishedIP = ip
	lastPublishedPort = port
	mu.Unlock()
	return writeEndpointToFirebase(hash, role, ip, port)
}

// getLocalPrivateIP returns the first non-loopback private IPv4 address found on the device.
func getLocalPrivateIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			var ip net.IP
			switch v := a.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ipv4 := ip.To4()
			if ipv4 == nil {
				continue
			}
			// RFC1918 private ranges
			if (ipv4[0] == 10) || (ipv4[0] == 172 && ipv4[1] >= 16 && ipv4[1] <= 31) || (ipv4[0] == 192 && ipv4[1] == 168) {
				return ipv4.String()
			}
		}
	}
	return ""
}

// encodeTunnelPayload length-prefixes an IP packet for safe streaming over DataChannel.
func encodeTunnelPayload(pkt []byte) []byte {
	var buf bytes.Buffer
	// 2-byte length prefix (big-endian) -> supports up to 65535 bytes
	binary.Write(&buf, binary.BigEndian, uint16(len(pkt)))
	buf.Write(pkt)
	return buf.Bytes()
}

// decodeTunnelPayload reads a single framed packet from a reader.
func decodeTunnelPayload(r io.Reader) ([]byte, error) {
	var l uint16
	if err := binary.Read(r, binary.BigEndian, &l); err != nil {
		return nil, err
	}
	pkt := make([]byte, int(l))
	if _, err := io.ReadFull(r, pkt); err != nil {
		return nil, err
	}
	return pkt, nil
}

// tunReadLoop reads raw IP packets from TUN and forwards to send func (DataChannel sender).
func tunReadLoop(ctx context.Context, send func([]byte) error) {
	if tunFile == nil {
		return
	}
	buf := make([]byte, 65535)
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		n, err := tunFile.Read(buf)
		if err != nil {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		framed := encodeTunnelPayload(buf[:n])
		_ = send(framed)
	}
}

// tunWriteLoop receives framed packets from recv (DataChannel reader) and writes to TUN.
func tunWriteLoop(ctx context.Context, recv func() ([]byte, error)) {
	if tunFile == nil {
		return
	}
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		framed, err := recv()
		if err != nil {
			time.Sleep(100 * time.Millisecond)
			continue
		}
		// decode using a bytes.Reader
		rdr := bytes.NewReader(framed)
		pkt, err := decodeTunnelPayload(rdr)
		if err != nil {
			continue
		}
		_, _ = tunFile.Write(pkt)
	}
}

// listenPeerEndpoint creates a persistent listener (SSE-like) on the firebase path for the peer.
// When peer data changes, onUpdate is invoked with the new ip/port if present.
func listenPeerEndpoint(hash, peerRole string, onUpdate func(string, int)) {
	// Firebase streaming uses the .json URL with Accept: text/event-stream
	url := fmt.Sprintf("%s/pairings/%s/%s.json", firebaseDB, hash, peerRole)
	for {
		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		req.Header.Set("Accept", "text/event-stream")
		client := &http.Client{Timeout: 0} // streaming
		resp, err := client.Do(req)
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		reader := bufio.NewReader(resp.Body)
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				break
			}
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "data: ") {
				data := strings.TrimPrefix(line, "data: ")
				// firebase may send "null" or JSON payload
				if data == "null" || data == "{}" {
					continue
				}
				var rec map[string]interface{}
				if err := json.Unmarshal([]byte(data), &rec); err != nil {
					continue
				}
				ip, _ := rec["ip"].(string)
				portf, _ := rec["port"].(float64)
				if ip != "" && portf > 0 {
					// also extract privateIp if present
					priv, _ := rec["privateIp"].(string)
					// call onUpdate including private ip as part of ip string via a small convention
					// we will instead call a variant that expects three args; update callers accordingly
					// For backward compatibility with existing callers, use a goroutine wrapper
					go func(ip string, port int, privateIp string) {
						// attempt type assertion for new signature via reflection-like approach not available
						// so call a typed helper via closure in StartEngine; here we just send via peerUpdateCh
						// Store peer info in status for other goroutines to consume
						mu.Lock()
						status["peerIp"] = ip
						status["peerPort"] = port
						status["peerPrivateIp"] = privateIp
						mu.Unlock()
						// notify listener
						select {
						case peerUpdateCh <- struct{}{}:
						default:
						}
					}(ip, int(portf), priv)
				}
			}
		}
		resp.Body.Close()
		// reconnect after a short backoff
		time.Sleep(2 * time.Second)
	}
}

// bridgeWebRTC is a placeholder that would perform WebRTC negotiation using Firebase signaling.
// For now it updates the status and triggers the read/write loops stubs.
func bridgeWebRTC(peerIP string, peerPort int, peerPrivateIP string) error {
	setStatus(map[string]interface{}{"state": "PUNCHING"})
	// If peerPrivateIP is supplied and public IPs match, prefer local LAN path.
	if peerPrivateIP != "" {
		setStatus(map[string]interface{}{"state": "CONNECTING_LOCAL", "peerIp": peerPrivateIP, "peerPort": peerPort})
		// In a real implementation we would open a direct TCP/UDP socket to peerPrivateIP:peerPort
		// or use WebRTC with local candidates. Here we simulate a quick success.
		time.Sleep(200 * time.Millisecond)
		setStatus(map[string]interface{}{"state": "CONNECTED", "peerIp": peerPrivateIP, "peerPort": peerPort, "lastHandshakeMs": time.Now().UnixMilli()})
		return nil
	}

	// Placeholder for Pion WebRTC negotiation via Firebase signaling.
	// A real implementation would:
	// 1. Create a PeerConnection, gather local ICE candidates
	// 2. Exchange SDP/ICE by writing/reading `/pairings/{hash}/sdp/{role}` in Firebase
	// 3. Open a DataChannel and start read/write loops using tunReadLoop/tunWriteLoop
	select {
	case peerUpdateCh <- struct{}{}:
	default:
	}
	time.Sleep(500 * time.Millisecond)
	setStatus(map[string]interface{}{"state": "CONNECTED", "peerIp": peerIP, "peerPort": peerPort, "lastHandshakeMs": time.Now().UnixMilli()})
	return nil
}

// heartbeatLoop periodically republishes our endpoint to Firebase to keep NAT bindings alive.
func heartbeatLoop(ctx context.Context, hash, role, ip string, port int) {
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = writeEndpointToFirebase(hash, role, ip, port)
		}
	}
}

// oppositeRole returns the expected peer role for a given role string.
func oppositeRole(role string) string {
	switch strings.ToLower(role) {
	case "client":
		return "server"
	case "server":
		return "client"
	case "master":
		return "slave"
	case "slave":
		return "master"
	case "left":
		return "right"
	case "right":
		return "left"
	case "initiator":
		return "responder"
	case "responder":
		return "initiator"
	default:
		return "peer"
	}
}

func updateStatus(m map[string]interface{}) {
	mu.Lock()
	defer mu.Unlock()
	for k, v := range m {
		status[k] = v
	}
}

//export StopEngine
func StopEngine() C.int {
	mu.Lock()
	if cancelFn != nil {
		cancelFn()
		cancelFn = nil
	}
	status = map[string]interface{}{"state": "DISCONNECTED"}
	mu.Unlock()
	return 0
}

//export NotifyNetworkChanged
func NotifyNetworkChanged() C.int {
	// On network change, republish our endpoint immediately and trigger re-negotiation.
	mu.Lock()
	pair, _ := status["pair"].(string)
	role, _ := status["role"].(string)
	mu.Unlock()
	updateStatus(map[string]interface{}{"state": "RECONNECTING"})
	go func() {
		// attempt to refresh and publish our endpoint
		_ = refreshAndPublishEndpoint(pair, role, 0)
		time.Sleep(500 * time.Millisecond)
		updateStatus(map[string]interface{}{"state": "CONNECTED", "lastHandshakeMs": time.Now().UnixMilli()})
	}()
	return 0
}

//export Java_com_shiva2232_orbitx_VpnBridge_notifyNetworkChanged
func Java_com_shiva2232_orbitx_VpnBridge_notifyNetworkChanged(env *C.JNIEnv, clazz C.jclass) C.jint {
	return NotifyNetworkChanged()
}

//export GetStatusJSON
func GetStatusJSON() *C.char {
	mu.Lock()
	b, _ := json.Marshal(status)
	mu.Unlock()
	return C.CString(string(b))
}

//export FreeCString
func FreeCString(ptr *C.char) {
	if ptr == nil {
		return
	}
	C.free(unsafe.Pointer(ptr))
}

func main() {}
