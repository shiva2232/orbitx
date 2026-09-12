//go:build linux

package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/db"
	"google.golang.org/api/option"

	"golang.zx2c4.com/wireguard/conn"
	"golang.zx2c4.com/wireguard/device"
	"golang.zx2c4.com/wireguard/tun"
	"golang.zx2c4.com/wireguard/z/utils"
)

const defaultDatabaseURL = "https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app"

func main() {
	mode := flag.String("m", "", "VPN mode: server or client")
	flag.Parse()

	isHost, err := modeIsHost(*mode)
	if err != nil {
		fatal(err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	databaseURL := envOrDefault("ORBITX_DATABASE_URL", defaultDatabaseURL)
	uuid := envOrDefault("ORBITX_UUID", "test123")
	deviceName := envOrDefault("ORBITX_DEVICE_NAME", "orbitx-ubuntu")
	interfaceName := envOrDefault("ORBITX_INTERFACE", "wg0")
	filesDir := envOrDefault("ORBITX_DATA_DIR", filepath.Join(userHome(), ".orbitx"))

	if err := os.MkdirAll(filesDir, 0700); err != nil {
		fatal(fmt.Errorf("create data directory: %w", err))
	}

	dbClient, err := firebaseClient(ctx, databaseURL)
	if err != nil {
		fatal(err)
	}

	keys := utils.NewKeyUtils(
		dbClient,
		isHost,
		deviceName,
		uuid,
		filepath.Join(filesDir, "orbitx_keys.json"),
	)
	if err := keys.Init(); err != nil {
		fatal(fmt.Errorf("initialize WireGuard keys: %w", err))
	}

	tunDevice, err := tun.CreateTUN(interfaceName, 1420)
	if err != nil {
		fatal(fmt.Errorf("create TUN interface %q: %w (run as root or grant CAP_NET_ADMIN)", interfaceName, err))
	}
	defer tunDevice.Close()

	internalIP := "10.0.0.2"
	if isHost {
		internalIP = "10.0.0.1"
	}
	if err := configureLinuxInterface(interfaceName, internalIP); err != nil {
		fatal(err)
	}

	bind := conn.NewDefaultBind()
	stdBind, ok := bind.(*conn.StdNetBind)
	if !ok {
		fatal(fmt.Errorf("failed to create the standard UDP bind"))
	}

	logger := device.NewLogger(device.LogLevelVerbose, "ORBITX: ")
	wgDevice := device.NewDevice(tunDevice, bind, logger)
	if err := wgDevice.Up(); err != nil {
		fatal(fmt.Errorf("start WireGuard device: %w", err))
	}
	defer wgDevice.Close()

	keys.OnStartVPN = func(config string) {
		if err := wgDevice.IpcSet(config); err != nil {
			fmt.Fprintf(os.Stderr, "orbitx: apply WireGuard configuration: %v\n", err)
			return
		}
		fmt.Println("orbitx: WireGuard configuration updated")
	}

	stunAddr, err := net.ResolveUDPAddr("udp", "stun.l.google.com:19302")
	if err != nil {
		fatal(fmt.Errorf("resolve STUN server: %w", err))
	}

	keys.StartVPNShared(ctx, func(packet []byte) error {
		return stdBind.SendStunPacket(packet, stunAddr)
	}, func(callback func([]byte, *net.UDPAddr)) {
		stdBind.OnStunPacket = callback
	})
	keys.StartPeerListener(ctx)

	role := "client"
	if isHost {
		role = "server"
	}
	fmt.Printf("orbitx: running as %s on %s\n", role, interfaceName)
	<-ctx.Done()
	keys.GetStunClient().Stop()
}

func firebaseClient(ctx context.Context, databaseURL string) (*db.Client, error) {
	app, err := firebase.NewApp(ctx, &firebase.Config{DatabaseURL: databaseURL}, option.WithoutAuthentication())
	if err != nil {
		return nil, fmt.Errorf("initialize Firebase: %w", err)
	}
	database, err := app.Database(ctx)
	if err != nil {
		return nil, fmt.Errorf("connect to Firebase: %w", err)
	}
	return database, nil
}

func modeIsHost(mode string) (bool, error) {
	switch mode {
	case "server":
		return true, nil
	case "client":
		return false, nil
	default:
		return false, fmt.Errorf("invalid mode %q: use -m server or -m client", mode)
	}
}

func configureLinuxInterface(interfaceName, internalIP string) error {
	commands := [][]string{
		{"addr", "replace", internalIP + "/24", "dev", interfaceName},
		{"link", "set", "dev", interfaceName, "up"},
		{"route", "replace", "10.0.0.0/24", "dev", interfaceName},
	}
	for _, args := range commands {
		output, err := exec.Command("ip", args...).CombinedOutput()
		if err != nil {
			return fmt.Errorf("configure TUN interface %q with ip %v: %w: %s", interfaceName, args, err, output)
		}
	}
	return nil
}

func envOrDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func userHome() string {
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return "."
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "orbitx:", err)
	os.Exit(1)
}
