//go:build !windows

package vpnengine


import (
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
	"golang.zx2c4.com/wireguard/z/utils"
)

var (
	mu            sync.Mutex
	wgDevice      *device.Device
	cancelCtx     context.CancelFunc
	keyUtils      *utils.KeyUtils
	dbURLState    string
	uuidState     string
	devNameState  string
	isHostState   bool
	filesDirState string
)

func Init(dbURL string, uuid string, deviceName string, isHost bool, filesDir string) string {
	mu.Lock()
	dbURLState = dbURL
	uuidState = uuid
	devNameState = deviceName
	isHostState = isHost
	filesDirState = filesDir
	mu.Unlock()

	ctx := context.Background()
	opt := option.WithoutAuthentication()

	app, err := firebase.NewApp(ctx, &firebase.Config{
		DatabaseURL: dbURL,
	}, opt)
	if err != nil {
		return fmt.Sprintf("failed to init firebase: %v", err)
	}

	dbClient, err := app.Database(ctx)
	if err != nil {
		return fmt.Sprintf("failed to init database: %v", err)
	}

	keysPath := filepath.Join(filesDir, "orbitx_keys.json")
	ku := utils.NewKeyUtils(dbClient, isHost, deviceName, uuid, keysPath)
	err = ku.Init()
	if err != nil {
		return fmt.Sprintf("failed to init key utils: %v", err)
	}

	mu.Lock()
	keyUtils = ku
	mu.Unlock()

	return ""
}

func Start(tunFd int) string {
	mu.Lock()
	ku := keyUtils
	mu.Unlock()

	if ku == nil {
		return "vpnengine not initialized. call Init() first"
	}

	Stop() // Make sure previous device is closed

	ctx, cancel := context.WithCancel(context.Background())
	logger := device.NewLogger(device.LogLevelVerbose, "VPN_ENGINE: ")

	// Wrap the Android TUN file descriptor
	file := os.NewFile(uintptr(tunFd), "tun")
	tunDev, err := tun.CreateTUNFromFile(file, 1420)
	if err != nil {
		cancel()
		return fmt.Sprintf("failed to create TUN device from fd %d: %v", tunFd, err)
	}

	bind := conn.NewDefaultBind()
	stdBind, ok := bind.(*conn.StdNetBind)
	if !ok {
		tunDev.Close()
		cancel()
		return "failed to cast Bind to StdNetBind"
	}

	wgDev := device.NewDevice(tunDev, bind, logger)
	err = wgDev.Up()
	if err != nil {
		wgDev.Close()
		cancel()
		return fmt.Sprintf("failed to bring up device: %v", err)
	}

	ku.OnStartVPN = func(config string) {
		mu.Lock()
		dev := wgDevice
		mu.Unlock()
		if dev != nil {
			err := dev.IpcSet(config)
			if err != nil {
				fmt.Printf("[vpnengine] Error applying WireGuard configuration: %v\n", err)
			} else {
				fmt.Println("[vpnengine] Successfully applied WireGuard configuration update")
			}
		}
	}

	stunAddr, err := net.ResolveUDPAddr("udp", "stun.l.google.com:19302")
	if err != nil {
		wgDev.Close()
		cancel()
		return fmt.Sprintf("failed to resolve STUN server: %v", err)
	}

	sendStun := func(packet []byte) error {
		return stdBind.SendStunPacket(packet, stunAddr)
	}

	registerOnStun := func(cb func([]byte, *net.UDPAddr)) {
		stdBind.OnStunPacket = cb
	}

	mu.Lock()
	wgDevice = wgDev
	cancelCtx = cancel
	mu.Unlock()

	// Start STUN UDP hole punching and peer listening
	ku.StartVPNShared(ctx, sendStun, registerOnStun)
	ku.StartPeerListener(ctx)

	return ""
}

func Stop() {
	mu.Lock()
	dev := wgDevice
	wgDevice = nil
	cancel := cancelCtx
	cancelCtx = nil
	ku := keyUtils
	mu.Unlock()

	if cancel != nil {
		cancel()
	}

	if ku != nil && ku.GetStunClient() != nil {
		ku.GetStunClient().Stop()
	}

	if dev != nil {
		dev.Close()
	}
}

func Exit() {
	Stop()
	mu.Lock()
	keyUtils = nil
	mu.Unlock()
}
