package main

import (
	"context"
	"fmt"
	"orbitx/utils"
	"os"
	"os/signal"
	"syscall"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"
)

func main() {
	GetStun(VpnConfig{
		isHost:     true,
		deviceName: "test",
		uuid:       "test123",
		callback: func(config string, fd int) {
		},
	})
	// Wait for Ctrl+C or SIGTERM
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)

	<-sig
}

type VpnConfig struct {
	isHost     bool
	deviceName string
	uuid       string
	callback   func(string, int)
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

	KeyUtils := utils.NewKeyUtils(dbClient, vpnConfig.isHost, vpnConfig.deviceName, vpnConfig.uuid)
	KeyUtils.Init()
	fd, err := KeyUtils.Pair(ctx, "")
	KeyUtils.OnStartVPN = func(str string) {
		vpnConfig.callback(str, fd)
	}
	fmt.Println(fd)
}
