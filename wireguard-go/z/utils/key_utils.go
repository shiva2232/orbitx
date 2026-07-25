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

	"golang.zx2c4.com/wireguard/shared"
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

	OnStartVPN func(config string)
	OnStopVPN  func()
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

func (k *KeyUtils) StartVPN(ctx context.Context, conn *net.UDPConn) {
	if conn != nil {
		k.conn = conn
	}
	k.stunClient.Start(conn, "stun.l.google.com", 19302, func(addr net.IP, port int, changed bool) {
		fmt.Println("port", port, addr, changed)
		if changed {
			fmt.Println("port", port, addr, changed)

			k.mu.Lock()
			k.current = &models.SignalingPeer{
				UID:                k.deviceName,
				PublicIP:           addr.String(),
				PublicPort:         port,
				WireguardPublicKey: k.publicKey,
				DeviceName:         k.deviceName,
				Online:             true,
				NetworkType:        "Go-Client",
				UpdatedAt:          time.Now().UnixMilli(),
				LastSeen:           time.Now().UnixMilli(),
				ProtocolVersion:    1,
			}
			id := k.uuid
			k.mu.Unlock()

			if id == "" {
				fmt.Println("id is empty")
				return
			}

			role := "peer"
			if k.isHost {
				role = "host"
			}

			fmt.Println("Updating peer info in database:", k.current)

			path := fmt.Sprintf("peers/%s/%s", id, role)
			_ = k.db.NewRef(path).Update(ctx, k.current.ToMap())
			k.Rerun()
		}
	})
}

func (k *KeyUtils) Rerun() {
	k.mu.Lock()
	p := k.peer
	c := k.current
	privKey := k.privateKey
	k.mu.Unlock()

	if p == nil || c == nil || privKey == "" {
		return
	}

	generator := &WireGuardConfigGenerator{}
	config := generator.Generate(models.WireGuardPeer{
		EndpointIP:    p.PublicIP,
		EndpointPort:  p.PublicPort,
		PeerPublicKey: p.WireguardPublicKey,
		MyPrivateKey:  privKey,
		MyAddress:     fmt.Sprintf("%s/32", c.PublicIP),
	}, "", "", 0)
	fmt.Println(config)
	if k.OnStartVPN != nil {
		k.OnStartVPN(config)
	}
}

func (k *KeyUtils) Pair(ctx context.Context, conn *net.UDPConn) (int, error) {
	k.mu.Lock()
	config := shared.GetConfig()
	k.uuid = config.Uuid
	k.isHost = config.IsHost
	k.mu.Unlock()

	k.StartVPN(ctx, nil)

	role := "host"
	if k.isHost {
		role = "peer"
	}
	path := fmt.Sprintf("peers/%s/%s", k.uuid, role)

	query := k.db.NewRef(path)

	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return

			case <-ticker.C:
				var data map[string]interface{}

				if err := query.Get(ctx, &data); err != nil {
					continue
				}
				if data == nil {
					continue
				}

				k.mu.Lock()
				prev := k.peer
				k.peer = &models.SignalingPeer{
					UID:                getString(data, "uid"),
					PublicIP:           getString(data, "publicIp"),
					PublicPort:         getInt(data, "publicPort"),
					WireguardPublicKey: getString(data, "wireguardPublicKey"),
					DeviceName:         getString(data, "deviceName"),
					Online:             getBool(data, "online"),
					NetworkType:        getString(data, "networkType"),
				}
				k.mu.Unlock()
				if prev == nil || k.peer != nil {
					k.Rerun()
					continue // or handle the first update specially
				} else if k.peer == nil {
					continue
				}
				if k.peer.PublicIP != prev.PublicIP || k.peer.PublicPort != prev.PublicPort || k.peer.WireguardPublicKey != prev.WireguardPublicKey {
					k.Rerun()
				}
			}
		}
	}()

	var fds int
	rawConn, _ := k.stunClient.Conn().SyscallConn()
	rawConn.Control(func(f uintptr) {
		fds = int(f)
	})

	return fds, nil
}

func (k *KeyUtils) StartVPNShared(ctx context.Context, sendStun func([]byte) error, registerOnStun func(func([]byte, *net.UDPAddr))) {
	registerOnStun(func(packet []byte, from *net.UDPAddr) {
		k.stunClient.ProcessPacket(packet)
	})

	k.stunClient.StartShared(sendStun, func(addr net.IP, port int, changed bool) {
		fmt.Println("port", port, addr, changed)
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
				fmt.Println("id is empty")
				return
			}

			role := "peer"
			if k.isHost {
				role = "host"
			}

			fmt.Println("Updating peer info in database:", k.current)

			path := fmt.Sprintf("peers/%s/%s", id, role)
			_ = k.db.NewRef(path).Update(ctx, k.current.ToMap())
			k.Rerun()
		}
	})
}

func (k *KeyUtils) StartPeerListener(ctx context.Context) {
	role := "host"
	if k.isHost {
		role = "peer"
	}
	path := fmt.Sprintf("peers/%s/%s", k.uuid, role)
	query := k.db.NewRef(path)

	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return

			case <-ticker.C:
				var data map[string]interface{}

				if err := query.Get(ctx, &data); err != nil {
					continue
				}
				if data == nil {
					continue
				}

				k.mu.Lock()
				prev := k.peer
				k.peer = &models.SignalingPeer{
					UID:                getString(data, "uid"),
					PublicIP:           getString(data, "publicIp"),
					PublicPort:         getInt(data, "publicPort"),
					WireguardPublicKey: getString(data, "wireguardPublicKey"),
					DeviceName:         getString(data, "deviceName"),
					Online:             getBool(data, "online"),
					NetworkType:        getString(data, "networkType"),
				}
				k.mu.Unlock()

				if prev == nil && k.peer != nil {
					k.Rerun()
				} else if prev != nil && k.peer != nil {
					if k.peer.PublicIP != prev.PublicIP || k.peer.PublicPort != prev.PublicPort || k.peer.WireguardPublicKey != prev.WireguardPublicKey {
						k.Rerun()
					}
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
	return 0
}

func getBool(m map[string]interface{}, key string) bool {
	if v, ok := m[key].(bool); ok {
		return v
	}
	return false
}
