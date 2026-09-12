package utils

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"sync"
	"time"

	"golang.zx2c4.com/wireguard/z/models"
	"golang.zx2c4.com/wireguard/z/stun"

	"firebase.google.com/go/v4/db"
	"golang.org/x/crypto/curve25519"
)

type KeyUtils struct {
	isHost     bool
	privateKey string
	publicKey  string
	stunClient *stun.StunClient
	db         *db.Client
	uuid       string
	deviceName string
	peer       *models.SignalingPeer
	current    *models.SignalingPeer
	mu         sync.Mutex
	conn       *net.UDPConn
	keysPath   string
	secret     string

	OnStartVPN func(config string)
	OnStopVPN  func()
}

func (k *KeyUtils) SetPresharedSecret(secret string) {
	k.mu.Lock()
	k.secret = secret
	k.mu.Unlock()
}

type Keys struct {
	PrivateKey string `json:"privateKey"`
	PublicKey  string `json:"publicKey"`
}

func NewKeyUtils(db *db.Client, isHost bool, deviceName string, uuid string, keysPath string) *KeyUtils {
	return &KeyUtils{
		db:         db,
		isHost:     isHost,
		deviceName: deviceName,
		stunClient: stun.NewStunClient(),
		uuid:       uuid,
		keysPath:   keysPath,
	}
}

func (k *KeyUtils) Init() error {
	return k.saveOrGetKey()
}

func (k *KeyUtils) generateKey() (string, string, error) {
	var priv [32]byte
	if _, err := rand.Read(priv[:]); err != nil {
		return "", "", err
	}

	var pub [32]byte
	curve25519.ScalarBaseMult(&pub, &priv)

	privB64 := base64.StdEncoding.EncodeToString(priv[:])
	pubB64 := base64.StdEncoding.EncodeToString(pub[:])

	return privB64, pubB64, nil
}

func (k *KeyUtils) saveOrGetKey() error {
	filename := k.keysPath
	if filename == "" {
		filename = "orbitx_keys.json"
	}
	data, err := os.ReadFile(filename)
	if err == nil {
		var keys Keys
		if err := json.Unmarshal(data, &keys); err == nil {
			k.privateKey = keys.PrivateKey
			k.publicKey = keys.PublicKey
			return nil
		}
	}

	priv, pub, err := k.generateKey()
	if err != nil {
		return err
	}
	k.privateKey = priv
	k.publicKey = pub

	keys := Keys{PrivateKey: priv, PublicKey: pub}
	data, _ = json.Marshal(keys)
	_ = os.WriteFile(filename, data, 0644)
	return nil
}

func (k *KeyUtils) StartVPNShared(ctx context.Context, sendStun func([]byte) error, registerOnStun func(func([]byte, *net.UDPAddr))) {
	registerOnStun(func(packet []byte, from *net.UDPAddr) {
		k.stunClient.ProcessPacket(packet)
	})

	k.stunClient.StartShared(sendStun, func(addr net.IP, port int, changed bool) {
		if changed {
			nowMilli := time.Now().UnixMilli()
			k.mu.Lock()
			k.current = &models.SignalingPeer{
				UID:                k.deviceName,
				PublicIP:           addr.String(),
				PublicPort:         port,
				WireguardPublicKey: k.publicKey,
				DeviceName:         k.deviceName,
				Online:             true,
				NetworkType:        "Go-Client",
				UpdatedAt:          nowMilli,
				LastSeen:           nowMilli,
				ProtocolVersion:    1,
			}
			id := k.uuid
			k.mu.Unlock()

			if id == "" {
				return
			}

			// Match the Android Firebase role names.
			role := "slave"
			if k.isHost {
				role = "master"
			}

			// FIX: Changed path from "peers" to "pairings"
			path := fmt.Sprintf("pairings/%s/%s", id, role)
			fmt.Printf("[vpnengine] Publishing local endpoint to Firebase: %s\n", path)

			err := k.db.NewRef(path).Update(ctx, k.current.ToMap())
			if err != nil {
				fmt.Printf("[vpnengine] Error publishing to Firebase: %v\n", err)
			}

			k.Rerun()
		}
	})
}

func (k *KeyUtils) Rerun() {
	k.mu.Lock()
	p := k.peer
	c := k.current
	privKey := k.privateKey
	muIsHost := k.isHost
	secret := k.secret
	k.mu.Unlock()

	if p == nil || c == nil || privKey == "" {
		return
	}
	if p.PublicIP == "" || p.PublicPort <= 0 || p.WireguardPublicKey == "" {
		fmt.Printf("[vpnengine] Peer data incomplete: endpoint=%s:%d publicKeyPresent=%t\n", p.PublicIP, p.PublicPort, p.WireguardPublicKey != "")
		return
	}

	// FIX: Use internal VPN IPs (10.0.0.x) instead of Public IPs for the Interface Address
	internalIP := "10.0.0.2"
	if muIsHost {
		internalIP = "10.0.0.1"
	}

	generator := &WireGuardConfigGenerator{}
	config := generator.GenerateWithPresharedKey(models.WireGuardPeer{
		EndpointIP:    p.PublicIP,
		EndpointPort:  p.PublicPort,
		PeerPublicKey: p.WireguardPublicKey,
		MyPrivateKey:  privKey,
		MyAddress:     fmt.Sprintf("%s/32", internalIP),
	}, "1.1.1.1", "10.0.0.1/32,10.0.0.2/32", 25, derivePresharedKey(k.uuid, secret))
	if config == "" {
		fmt.Println("[vpnengine] Failed to generate WireGuard configuration: invalid key encoding")
		return
	}

	if k.OnStartVPN != nil {
		k.OnStartVPN(config)
	}
}

func (k *KeyUtils) StartPeerListener(ctx context.Context) {
	role := "master"
	if k.isHost {
		role = "slave"
	}

	// FIX: Changed path from "peers" to "pairings"
	path := fmt.Sprintf("pairings/%s/%s", k.uuid, role)
	query := k.db.NewRef(path)

	fmt.Printf("[vpnengine] Starting peer listener on Firebase: %s\n", path)

	go func() {
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				var data map[string]interface{}
				if err := query.Get(ctx, &data); err != nil {
					fmt.Printf("[vpnengine] Firebase peer lookup failed: %v\n", err)
					continue
				}
				if data == nil {
					fmt.Printf("[vpnengine] No peer data at %s\n", path)
					continue
				}

				k.mu.Lock()
				var previous models.SignalingPeer
				if k.peer != nil {
					previous = *k.peer
				}
				k.peer = &models.SignalingPeer{
					UID:                getString(data, "uid"),
					PublicIP:           getString(data, "publicIp"),
					PublicPort:         getInt(data, "publicPort"),
					WireguardPublicKey: getString(data, "wireguardPublicKey"),
					DeviceName:         getString(data, "deviceName"),
					Online:             getBool(data, "online"),
					NetworkType:        getString(data, "networkType"),
				}
				peer := *k.peer
				k.mu.Unlock()

				changed := previous.PublicIP == "" || peer.PublicIP != previous.PublicIP || peer.PublicPort != previous.PublicPort || peer.WireguardPublicKey != previous.WireguardPublicKey
				if changed {
					fmt.Printf("[vpnengine] Peer endpoint updated: %s:%d publicKeyPresent=%t\n", peer.PublicIP, peer.PublicPort, peer.WireguardPublicKey != "")
					k.Rerun()
				}
			}
		}
	}()
}

func (k *KeyUtils) GetStunClient() *stun.StunClient {
	return k.stunClient
}

func getString(m map[string]interface{}, key string) string {
	if v, ok := m[key].(string); ok {
		return v
	}
	return ""
}

func getInt(m map[string]interface{}, key string) int {
	if v, ok := m[key].(float64); ok {
		return int(v)
	}
	if v, ok := m[key].(int); ok {
		return v
	}
	return 0
}

func getBool(m map[string]interface{}, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}
