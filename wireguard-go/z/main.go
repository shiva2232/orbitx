package z

import (
	"context"
	"os"
	"os/signal"
	"syscall"

	"golang.zx2c4.com/wireguard/z/utils"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"
)

func main(config VpnConfig) {
	GetStun(VpnConfig{
		IsHost:     true,
		DeviceName: "test",
		Uuid:       "test123",
		Callback: func(config string) {
		},
	})
	// Wait for Ctrl+C or SIGTERM
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)

	<-sig
}

type VpnConfig struct {
	IsHost     bool
	DeviceName string
	Uuid       string
	Callback   func(string)
}

func GetStun(vpnConfig VpnConfig) {
	ctx := context.Background()

	opt := option.WithoutAuthentication()

	app, err := firebase.NewApp(ctx, &firebase.Config{
		DatabaseURL: "https://orbitx-os-default-rtdb.asia-southeast1.firebasedatabase.app",
	}, opt)
	if err != nil {
		panic(err)
	}
	dbClient, err := app.Database(ctx)
	if err != nil {
		panic(err)
	}

	KeyUtils := utils.NewKeyUtils(dbClient, vpnConfig.IsHost, vpnConfig.DeviceName, vpnConfig.Uuid, "")
	KeyUtils.Init()
	KeyUtils.OnStartVPN = func(str string) {
		vpnConfig.Callback(str)
	}
}
