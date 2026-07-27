package main

/*
#include <stdlib.h>
#include <jni.h>

static JavaVM* vpn_jvm = NULL;
static jclass home_vpn_service_class = NULL;

static const char* GetStringUTFCharsC(JNIEnv *env, jstring str) {
	if (str == NULL) return NULL;
	return (*env)->GetStringUTFChars(env, str, NULL);
}

static void ReleaseStringUTFCharsC(JNIEnv *env, jstring str, const char* chars) {
	if (str == NULL || chars == NULL) return;
	(*env)->ReleaseStringUTFChars(env, str, chars);
}

static void SaveJavaVMAndServiceClass(JNIEnv *env) {
	if (env == NULL) return;
	(*env)->GetJavaVM(env, &vpn_jvm);
	if (home_vpn_service_class != NULL) return;

	jclass local = (*env)->FindClass(env, "com/shiva2232/orbitx/HomeVpnService");
	if ((*env)->ExceptionCheck(env)) {
		(*env)->ExceptionClear(env);
		return;
	}
	if (local == NULL) return;

	home_vpn_service_class = (*env)->NewGlobalRef(env, local);
	(*env)->DeleteLocalRef(env, local);
}

static int ProtectSocketFdC(int fd) {
	if (vpn_jvm == NULL || home_vpn_service_class == NULL) return 0;
	JNIEnv *env = NULL;
	int shouldDetach = 0;
	jint envRes = (*vpn_jvm)->GetEnv(vpn_jvm, (void**)&env, JNI_VERSION_1_6);
	if (envRes == JNI_EDETACHED) {
		if ((*vpn_jvm)->AttachCurrentThread(vpn_jvm, &env, NULL) != JNI_OK) return 0;
		shouldDetach = 1;
	} else if (envRes != JNI_OK) {
		return 0;
	}

	jmethodID method = (*env)->GetStaticMethodID(env, home_vpn_service_class, "protectSocketFromNative", "(I)Z");
	if ((*env)->ExceptionCheck(env)) {
		(*env)->ExceptionClear(env);
		if (shouldDetach) (*vpn_jvm)->DetachCurrentThread(vpn_jvm);
		return 0;
	}
	if (method == NULL) {
		if (shouldDetach) (*vpn_jvm)->DetachCurrentThread(vpn_jvm);
		return 0;
	}

	jboolean protected = (*env)->CallStaticBooleanMethod(env, home_vpn_service_class, method, (jint)fd);
	if ((*env)->ExceptionCheck(env)) {
		(*env)->ExceptionClear(env);
		protected = JNI_FALSE;
	}

	if (shouldDetach) (*vpn_jvm)->DetachCurrentThread(vpn_jvm);
	return protected == JNI_TRUE ? 1 : 0;
}

static jstring NewStringUTFCharsC(JNIEnv *env, const char* value) {
	if (env == NULL || value == NULL) return NULL;
	return (*env)->NewStringUTF(env, value);
}
*/
import "C"

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/crypto/curve25519"
	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
)

var (
	mu           sync.Mutex
	tunFd        int
	wgDevice     *device.Device
	cancelFn     context.CancelFunc
	status       = map[string]interface{}{"state": "DISCONNECTED"}
	firebaseDB   = "https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app"
	stunBind     *conn.StdNetBind
	stunAddr     *net.UDPAddr
	stunServer   = "stun.l.google.com:19302"
	peerUpdateCh = make(chan struct{}, 1)
	forceStunCh  = make(chan struct{}, 1)

	privateKey   [32]byte
	publicKey    [32]byte
	presharedKey [32]byte
)

func init() {
	// Register socket protector to ensure Go network traffic bypasses the VPN tunnel
	conn.RegisterControlFn(func(network, address string, c syscall.RawConn) error {
		return c.Control(func(fd uintptr) {
			C.ProtectSocketFdC(C.int(fd))
		})
	})
}

//export SubmitTunFd
func SubmitTunFd(fd C.int) C.int {
	mu.Lock()
	defer mu.Unlock()
	tunFd = int(fd)
	status["state"] = "TUN_READY"
	return 0
}

//export Java_com_shiva2232_orbitx_VpnBridge_submitTunFd
func Java_com_shiva2232_orbitx_VpnBridge_submitTunFd(env *C.JNIEnv, clazz C.jclass, fd C.jint) C.jint {
	C.SaveJavaVMAndServiceClass(env)
	return SubmitTunFd(fd)
}

//export Java_com_shiva2232_orbitx_VpnBridge_startEngine
func Java_com_shiva2232_orbitx_VpnBridge_startEngine(env *C.JNIEnv, clazz C.jclass, cpair C.jstring, crole C.jstring, csecret C.jstring) C.jint {
	C.SaveJavaVMAndServiceClass(env)
	p := C.GetStringUTFCharsC(env, cpair)
	r := C.GetStringUTFCharsC(env, crole)
	s := C.GetStringUTFCharsC(env, csecret)

	pair := C.GoString(p)
	role := C.GoString(r)
	secret := C.GoString(s)

	C.ReleaseStringUTFCharsC(env, cpair, p)
	C.ReleaseStringUTFCharsC(env, crole, r)
	C.ReleaseStringUTFCharsC(env, csecret, s)

	return StartEngine(C.CString(pair), C.CString(role), C.CString(secret))
}

//export Java_com_shiva2232_orbitx_VpnBridge_stopEngine
func Java_com_shiva2232_orbitx_VpnBridge_stopEngine(env *C.JNIEnv, clazz C.jclass) C.jint {
	return StopEngine()
}

//export Java_com_shiva2232_orbitx_VpnBridge_getStatusJSON
func Java_com_shiva2232_orbitx_VpnBridge_getStatusJSON(env *C.JNIEnv, clazz C.jclass) C.jstring {
	value := C.CString(statusJSON())
	defer C.free(unsafe.Pointer(value))
	return C.NewStringUTFCharsC(env, value)
}

//export StartEngine
func StartEngine(cpair *C.char, crole *C.char, csecret *C.char) C.int {
	pair := C.GoString(cpair)
	role := C.GoString(crole)
	secret := C.GoString(csecret)
	C.free(unsafe.Pointer(cpair))
	C.free(unsafe.Pointer(crole))
	if csecret != nil {
		C.free(unsafe.Pointer(csecret))
	}
	if pair == "" || secret == "" {
		return -1
	}
	deriveIdentity(pair, role, secret)

	mu.Lock()
	if tunFd <= 0 {
		mu.Unlock()
		return -2
	}
	if cancelFn != nil {
		cancelFn()
	}
	var ctx context.Context
	ctx, cancelFn = context.WithCancel(context.Background())
	mu.Unlock()

	// Android's VpnService has already created and configured this TUN file
	// descriptor. CreateTUNFromFile starts a NETLINK_ROUTE monitor, which an
	// unprivileged Android app is not allowed to bind, preventing the engine
	// from ever reaching its Firebase bootstrap publish.
	tunDev, _, err := tun.CreateUnmonitoredTUNFromFD(tunFd)
	if err != nil {
		log.Printf("[vpnengine] CreateTUN failed: %v", err)
		return -3
	}

	bind := conn.NewDefaultBind()
	stdBind, ok := bind.(*conn.StdNetBind)
	if !ok {
		return -4
	}
	logger := device.NewLogger(device.LogLevelVerbose, "VPN_GO: ")
	wgDev := device.NewDevice(tunDev, bind, logger)

	mu.Lock()
	wgDevice = wgDev
	stunBind = stdBind
	status["state"] = "CONNECTING"
	mu.Unlock()

	if err := wgDev.IpcSet("listen_port=0\n"); err != nil {
		wgDev.Close()
		return -5
	}
	if err := wgDev.Up(); err != nil {
		wgDev.Close()
		return -6
	}

	stdBind.OnStunPacket = func(packet []byte, _ *net.UDPAddr) {
		if ip, port, err := parseStunResponse(packet); err == nil {
			updateLocalEndpoint(pair, role, ip, port)
		}
	}
	if addr, err := net.ResolveUDPAddr("udp", stunServer); err == nil {
		stunAddr = addr
	}

	// Bootstrap Write: Publish public key immediately so peer can see us
	log.Printf("[vpnengine] Performing bootstrap publish for role: %s", role)
	writeEndpointToFirebase(pair, role, "0.0.0.0", 0)

	go heartbeatLoop(ctx, pair, role)
	go listenPeerEndpoint(ctx, pair, oppositeRole(role))

	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case <-peerUpdateCh:
				mu.Lock()
				pip, _ := status["peerIp"].(string)
				pport, _ := status["peerPort"].(int)
				pubKeyB64, _ := status["peerPublicKey"].(string)
				mu.Unlock()

				if pip != "" && pport > 0 && pubKeyB64 != "" {
					applyWireGuardConfig(wgDev, pip, pport, pubKeyB64)
				}
			}
		}
	}()

	return 0
}

func applyWireGuardConfig(dev *device.Device, ip string, port int, pubKeyB64 string) {
	pubKeyBytes, err := base64.StdEncoding.DecodeString(pubKeyB64)
	if err != nil || len(pubKeyBytes) != 32 {
		return
	}

	pubKeyHex := hex.EncodeToString(pubKeyBytes)
	privKeyHex := hex.EncodeToString(privateKey[:])
	pskHex := hex.EncodeToString(derivePresharedKey())

	uapi := fmt.Sprintf("private_key=%s\nreplace_peers=true\npublic_key=%s\npreshared_key=%s\nendpoint=%s:%d\nreplace_allowed_ips=true\nallowed_ip=10.0.0.1/32\nallowed_ip=10.0.0.2/32\npersistent_keepalive_interval=15\n",
		privKeyHex, pubKeyHex, pskHex, ip, port)

	if err := dev.IpcSet(uapi); err != nil {
		log.Printf("[vpnengine] UAPI Error: %v", err)
	} else {
		updateStatus(map[string]interface{}{"state": "CONNECTED", "peerIp": ip, "peerPort": port})
		log.Printf("[vpnengine] Connected to peer: %s:%d", ip, port)
	}
}

func writeEndpointToFirebase(hash, role, ip string, port int) {
	url := fmt.Sprintf("%s/pairings/%s/%s.json", firebaseDB, hash, normalizeRole(role))
	payload := map[string]interface{}{
		"publicIp":           ip,
		"publicPort":         port,
		"wireguardPublicKey": base64.StdEncoding.EncodeToString(publicKey[:]),
		"updatedAt":          time.Now().UnixMilli(),
		"online":             true,
	}
	b, _ := json.Marshal(payload)

	req, err := http.NewRequest(http.MethodPut, url, bytes.NewReader(b))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")

	client := protectedHTTPClient(10 * time.Second)
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[vpnengine] Firebase Write Error: %v", err)
		return
	}
	resp.Body.Close()
	log.Printf("[vpnengine] Firebase Updated for %s: %s:%d", role, ip, port)
}

func listenPeerEndpoint(ctx context.Context, hash, peerRole string) {
	url := fmt.Sprintf("%s/pairings/%s/%s.json", firebaseDB, hash, normalizeRole(peerRole))
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		req.Header.Set("Accept", "text/event-stream")
		client := protectedHTTPClient(0)
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
				if data == "null" || data == "{}" {
					continue
				}
				var event map[string]interface{}
				if err := json.Unmarshal([]byte(data), &event); err != nil {
					continue
				}

				target := event
				if d, ok := event["data"].(map[string]interface{}); ok {
					target = d
				}

				ip, _ := target["publicIp"].(string)
				port, _ := target["publicPort"].(float64)
				pubKey, _ := target["wireguardPublicKey"].(string)

				if pubKey != "" && ip != "" && ip != "0.0.0.0" && port > 0 {
					mu.Lock()
					oldIP, _ := status["peerIp"].(string)
					oldPort, _ := status["peerPort"].(int)
					oldKey, _ := status["peerPublicKey"].(string)
					status["peerIp"] = ip
					status["peerPort"] = int(port)
					status["peerPublicKey"] = pubKey
					mu.Unlock()
					if oldIP != ip || oldPort != int(port) || oldKey != pubKey {
						log.Printf("[vpnengine] Peer endpoint changed: %s:%d", ip, int(port))
						select {
						case peerUpdateCh <- struct{}{}:
						default:
						}
					}
				}
			}
		}
		resp.Body.Close()
		time.Sleep(2 * time.Second)
	}
}

func heartbeatLoop(ctx context.Context, hash, role string) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()
	for {
		requestStunBinding()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		case <-forceStunCh:
		}
	}
}

func requestStunBinding() {
	mu.Lock()
	bind, addr := stunBind, stunAddr
	mu.Unlock()
	if bind == nil || addr == nil {
		return
	}
	req := make([]byte, 20)
	binary.BigEndian.PutUint16(req[0:2], 0x0001)
	binary.BigEndian.PutUint32(req[4:8], 0x2112A442)
	txid := make([]byte, 12)
	rand.Read(txid)
	copy(req[8:20], txid)
	_ = bind.SendStunPacket(req, addr)
}

func parseStunResponse(resp []byte) (string, int, error) {
	n := len(resp)
	if n < 20 {
		return "", 0, fmt.Errorf("short STUN response")
	}
	pos := 20
	for pos+4 <= n {
		atype := binary.BigEndian.Uint16(resp[pos : pos+2])
		alen := int(binary.BigEndian.Uint16(resp[pos+2 : pos+4]))
		pos += 4
		if atype == 0x0020 && alen >= 8 {
			xport := binary.BigEndian.Uint16(resp[pos+2 : pos+4])
			port := int(xport ^ (0x2112))
			xaddr := binary.BigEndian.Uint32(resp[pos+4 : pos+8])
			ipInt := xaddr ^ 0x2112A442
			ip := net.IPv4(byte(ipInt>>24), byte(ipInt>>16), byte(ipInt>>8), byte(ipInt)).String()
			return ip, port, nil
		}
		pos += (alen + 3) &^ 3
	}
	return "", 0, fmt.Errorf("no XOR-MAPPED-ADDRESS")
}

func updateLocalEndpoint(hash, role, ip string, port int) {
	mu.Lock()
	previousIP, _ := status["publicIp"].(string)
	previousPort, _ := status["publicPort"].(int)
	status["publicIp"], status["publicPort"] = ip, port
	mu.Unlock()
	if previousIP != ip || previousPort != port {
		writeEndpointToFirebase(hash, role, ip, port)
	}
}

func deriveIdentity(pair, role, secret string) {
	seed := sha256.Sum256([]byte("orbitx/wireguard/private/" + pair + "/" + normalizeRole(role) + "/" + secret))
	copy(privateKey[:], seed[:])
	privateKey[0] &= 248
	privateKey[31] &= 127
	privateKey[31] |= 64
	curve25519.ScalarBaseMult(&publicKey, &privateKey)
	presharedKey = sha256.Sum256([]byte("orbitx/wireguard/psk/" + pair + "/" + secret))
}

func derivePresharedKey() []byte {
	return presharedKey[:]
}

func protectedHTTPClient(timeout time.Duration) *http.Client {
	dialer := &net.Dialer{
		Timeout: timeout,
		Control: func(network, address string, conn syscall.RawConn) error {
			return conn.Control(func(fd uintptr) { C.ProtectSocketFdC(C.int(fd)) })
		},
	}
	return &http.Client{
		Timeout:   timeout,
		Transport: &http.Transport{DialContext: dialer.DialContext},
	}
}

func normalizeRole(role string) string {
	r := strings.ToLower(role)
	if r == "host" || r == "master" {
		return "master"
	}
	return "slave"
}

func oppositeRole(role string) string {
	if normalizeRole(role) == "master" {
		return "slave"
	}
	return "master"
}

func updateStatus(m map[string]interface{}) {
	mu.Lock()
	defer mu.Unlock()
	for k, v := range m {
		status[k] = v
	}
}

func statusJSON() string {
	mu.Lock()
	defer mu.Unlock()
	value, err := json.Marshal(status)
	if err != nil {
		return `{"state":"UNKNOWN"}`
	}
	return string(value)
}

//export GetStatusJSON
func GetStatusJSON() *C.char {
	return C.CString(statusJSON())
}

//export FreeCString
func FreeCString(value *C.char) {
	if value != nil {
		C.free(unsafe.Pointer(value))
	}
}

//export StopEngine
func StopEngine() C.int {
	mu.Lock()
	if cancelFn != nil {
		cancelFn()
	}
	if wgDevice != nil {
		wgDevice.Close()
		wgDevice = nil
	}
	stunBind = nil
	stunAddr = nil
	status = map[string]interface{}{"state": "DISCONNECTED"}
	mu.Unlock()
	return 0
}

//export Java_com_shiva2232_orbitx_VpnBridge_notifyNetworkChanged
func Java_com_shiva2232_orbitx_VpnBridge_notifyNetworkChanged(env *C.JNIEnv, clazz C.jclass) C.jint {
	select {
	case forceStunCh <- struct{}{}:
	default:
	}
	return 0
}

func main() {}
