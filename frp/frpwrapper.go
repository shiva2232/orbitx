package main

/*
#include <jni.h>
#include <stdlib.h>

static const char* GetStringUTFChars(JNIEnv* env, jstring str, jboolean* isCopy) {
    return (*env)->GetStringUTFChars(env, str, isCopy);
}

static void ReleaseStringUTFChars(JNIEnv* env, jstring str, const char* chars) {
    (*env)->ReleaseStringUTFChars(env, str, chars);
}
*/
import "C"

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

// StartFrpc runs the FRP client
func StartFrpc(configContent string) error {
	frpcMu.Lock()
	if frpcCancel != nil {
		frpcMu.Unlock()
		return fmt.Errorf("frpc is already running")
	}

	ctx, cancel := context.WithCancel(context.Background())
	frpcCancel = cancel
	frpcMu.Unlock()

	defer func() {
		frpcMu.Lock()
		frpcCancel = nil
		frpcMu.Unlock()
	}()

	tmpFile, err := os.CreateTemp("", "frpc-*.toml")
	if err != nil {
		return err
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(configContent); err != nil {
		tmpFile.Close()
		return err
	}
	tmpFile.Close()

	svr, err := client.NewService(client.ServiceOptions{
		ConfigFilePath: tmpFile.Name(),
	})
	if err != nil {
		return err
	}

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

// --- JNI Exports ---

//export Java_frpwrapper_Frpwrapper_startFrps
func Java_frpwrapper_Frpwrapper_startFrps(env *C.JNIEnv, clazz C.jclass, config C.jstring) {
	cConfig := C.GetStringUTFChars(env, config, nil)
	defer C.ReleaseStringUTFChars(env, config, cConfig)
	_ = StartFrps(C.GoString(cConfig))
}

//export Java_frpwrapper_Frpwrapper_stopFrps
func Java_frpwrapper_Frpwrapper_stopFrps(env *C.JNIEnv, clazz C.jclass) {
	StopFrps()
}

//export Java_frpwrapper_Frpwrapper_startFrpc
func Java_frpwrapper_Frpwrapper_startFrpc(env *C.JNIEnv, clazz C.jclass, config C.jstring) {
	cConfig := C.GetStringUTFChars(env, config, nil)
	defer C.ReleaseStringUTFChars(env, config, cConfig)
	_ = StartFrpc(C.GoString(cConfig))
}

//export Java_frpwrapper_Frpwrapper_stopFrpc
func Java_frpwrapper_Frpwrapper_stopFrpc(env *C.JNIEnv, clazz C.jclass) {
	StopFrpc()
}

func main() {}
