package frpwrapper

import (
	"context"
	"fmt"
	"os"
	"sync"

	"github.com/fatedier/frp/client"
	"github.com/fatedier/frp/pkg/config"
	"github.com/fatedier/frp/server"
)

var (
	frpsCancel context.CancelFunc
	frpsMu     sync.Mutex
)

var (
	frpcCancel context.CancelFunc
	frpcMu     sync.Mutex
)

// StartFrps runs the server service
func StartFrps(configContent string) error {
	frpsMu.Lock()
	if frpsCancel != nil {
		frpsMu.Unlock()
		return fmt.Errorf("frps is already running")
	}

	ctx, cancel := context.WithCancel(context.Background())
	frpsCancel = cancel
	frpsMu.Unlock()

	defer func() {
		frpsMu.Lock()
		frpsCancel = nil
		frpsMu.Unlock()
	}()

	tmpFile, err := os.CreateTemp("", "frps-*.toml")
	if err != nil {
		return err
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(configContent); err != nil {
		tmpFile.Close()
		return err
	}
	tmpFile.Close()

	cfg, _, err := config.LoadServerConfig(tmpFile.Name(), false)
	if err != nil {
		return err
	}

	svr, err := server.NewService(cfg)
	if err != nil {
		return err
	}

	// Correct for Server: svr.Run() takes NO arguments and has NO return value
	svr.Run(ctx)
	return nil
}

// StopFrps cancels the context and gracefully shuts down the server
func StopFrps() {
	frpsMu.Lock()
	defer frpsMu.Unlock()

	if frpsCancel != nil {
		frpsCancel()
		frpsCancel = nil
	}
}

// StartFrpc runs the FRP client from an in-memory configuration string
func StartFrpc(configContent string) error {
	frpcMu.Lock()
	if frpcCancel != nil {
		frpcMu.Unlock()
		return fmt.Errorf("frpc is already running")
	}

	ctx, cancel := context.WithCancel(context.Background())
	frpcCancel = cancel
	frpcMu.Unlock()

	// Ensure cleanup of cancellation state when frpc exits
	defer func() {
		frpcMu.Lock()
		frpcCancel = nil
		frpcMu.Unlock()
	}()
	// 1. Create a temporary TOML file
	tmpFile, err := os.CreateTemp("", "frpc-*.toml")
	if err != nil {
		return err
	}
	defer os.Remove(tmpFile.Name()) // Clean up after execution

	// 2. Write the config string into the temp file
	if _, err := tmpFile.WriteString(configContent); err != nil {
		tmpFile.Close()
		return err
	}
	tmpFile.Close()

	// 3. Pass ConfigFilePath directly to ServiceOptions
	svr, err := client.NewService(client.ServiceOptions{
		ConfigFilePath: tmpFile.Name(),
	})
	if err != nil {
		return err
	}

	// 4. Run the client service with context
	return svr.Run(ctx)
}

// StopFrpc cancels the context and gracefully shuts down the client
func StopFrpc() {
	frpcMu.Lock()
	defer frpcMu.Unlock()

	if frpcCancel != nil {
		frpcCancel()
		frpcCancel = nil
	}
}
