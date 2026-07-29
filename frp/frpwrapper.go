package main

/*
#cgo LDFLAGS: -llog

#include <jni.h>
#include <stdlib.h>
#include <android/log.h>

#define LOG_TAG "FRP_NATIVE"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static const char* GetStringUTFChars(JNIEnv* env, jstring str, jboolean* isCopy) {
    if (str == NULL) return NULL;
    return (*env)->GetStringUTFChars(env, str, isCopy);
}

static void ReleaseStringUTFChars(JNIEnv* env, jstring str, const char* chars) {
    if (env == NULL || str == NULL || chars == NULL) return;
    (*env)->ReleaseStringUTFChars(env, str, chars);
}

static void log_info(const char* msg) { LOGI("%s", msg); }
static void log_error(const char* msg) { LOGE("%s", msg); }
*/
import "C"

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"github.com/fatedier/frp/client"
	"github.com/fatedier/frp/pkg/config"
	"github.com/fatedier/frp/server"
)

var (
	frpsCancel  context.CancelFunc
	frpsMu      sync.Mutex
	frpsRunning bool
	frpsSvr     *server.Service

	frpcCancel  context.CancelFunc
	frpcMu      sync.Mutex
	frpcRunning bool
	frpcSvr     *client.Service

	workDir string
	logOnce sync.Once
)

func logInfo(msg string) {
	cmsg := C.CString(msg)
	C.log_info(cmsg)
	C.free(unsafe.Pointer(cmsg))
}

func logError(msg string) {
	cmsg := C.CString(msg)
	C.log_error(cmsg)
	C.free(unsafe.Pointer(cmsg))
}

func redirectLogs() {
	r, w, _ := os.Pipe()
	os.Stdout = w
	os.Stderr = w
	go func() {
		scanner := bufio.NewScanner(r)
		for scanner.Scan() {
			logInfo("[FRP-CORE] " + scanner.Text())
		}
	}()
}

func StartFrps(configContent string) error {
	frpsMu.Lock()
	if frpsCancel != nil {
		frpsMu.Unlock()
		return fmt.Errorf("frps is already running")
	}
	ctx, cancel := context.WithCancel(context.Background())
	frpsCancel = cancel
	frpsRunning = true
	frpsMu.Unlock()

	defer func() {
		frpsMu.Lock()
		frpsCancel = nil
		frpsRunning = false
		frpsSvr = nil
		frpsMu.Unlock()
	}()

	if workDir == "" {
		return fmt.Errorf("workDir not initialized")
	}

	tmpPath := filepath.Join(workDir, "frps.toml")
	if err := os.WriteFile(tmpPath, []byte(configContent), 0644); err != nil {
		return err
	}
	defer os.Remove(tmpPath)

	cfg, _, err := config.LoadServerConfig(tmpPath, false)
	if err != nil {
		return err
	}

	svr, err := server.NewService(cfg)
	if err != nil {
		return err
	}

	frpsMu.Lock()
	frpsSvr = svr
	frpsMu.Unlock()

	logInfo(fmt.Sprintf("FRPS starting on %s:%d", cfg.BindAddr, cfg.BindPort))
	svr.Run(ctx)
	return nil
}

func StartFrpc(configContent string) error {
	frpcMu.Lock()
	if frpcCancel != nil {
		frpcMu.Unlock()
		return fmt.Errorf("frpc is already running")
	}
	ctx, cancel := context.WithCancel(context.Background())
	frpcCancel = cancel
	frpcRunning = true
	frpcMu.Unlock()

	defer func() {
		frpcMu.Lock()
		frpcCancel = nil
		frpcRunning = false
		frpcSvr = nil
		frpcMu.Unlock()
	}()

	if workDir == "" {
		return fmt.Errorf("workDir not initialized")
	}

	tmpPath := filepath.Join(workDir, "frpc.toml")
	if err := os.WriteFile(tmpPath, []byte(configContent), 0644); err != nil {
		return err
	}
	defer os.Remove(tmpPath)

	svr, err := client.NewService(client.ServiceOptions{
		ConfigFilePath: tmpPath,
	})
	if err != nil {
		return err
	}

	frpcMu.Lock()
	frpcSvr = svr
	frpcMu.Unlock()

	logInfo("FRPC starting...")
	svr.Run(ctx)
	return nil
}

// --- JNI Exports ---

//export Java_frpwrapper_Frpwrapper_init
func Java_frpwrapper_Frpwrapper_init(env *C.JNIEnv, clazz C.jclass, cacheDir C.jstring) {
	cStr := C.GetStringUTFChars(env, cacheDir, nil)
	if cStr != nil {
		workDir = C.GoString(cStr)
		C.ReleaseStringUTFChars(env, cacheDir, cStr)
	}
	logOnce.Do(redirectLogs)
	logInfo(fmt.Sprintf("FRP Native Initialized. WorkDir: %s", workDir))
}

//export Java_frpwrapper_Frpwrapper_startFrps
func Java_frpwrapper_Frpwrapper_startFrps(env *C.JNIEnv, clazz C.jclass, config C.jstring) {
	cStr := C.GetStringUTFChars(env, config, nil)
	if cStr == nil { return }
	goConfig := C.GoString(cStr)
	C.ReleaseStringUTFChars(env, config, cStr)

	go func() {
		if err := StartFrps(goConfig); err != nil {
			logError(fmt.Sprintf("FRPS Fatal Error: %v", err))
		}
	}()
}

//export Java_frpwrapper_Frpwrapper_stopFrps
func Java_frpwrapper_Frpwrapper_stopFrps(env *C.JNIEnv, clazz C.jclass) {
	frpsMu.Lock()
	if frpsCancel != nil {
		frpsCancel()
		frpsCancel = nil
	}
	if frpsSvr != nil {
		frpsSvr.Close()
	}
	frpsMu.Unlock()
}

//export Java_frpwrapper_Frpwrapper_startFrpc
func Java_frpwrapper_Frpwrapper_startFrpc(env *C.JNIEnv, clazz C.jclass, config C.jstring) {
	cStr := C.GetStringUTFChars(env, config, nil)
	if cStr == nil { return }
	goConfig := C.GoString(cStr)
	C.ReleaseStringUTFChars(env, config, cStr)

	go func() {
		if err := StartFrpc(goConfig); err != nil {
			logError(fmt.Sprintf("FRPC Fatal Error: %v", err))
		}
	}()
}

//export Java_frpwrapper_Frpwrapper_stopFrpc
func Java_frpwrapper_Frpwrapper_stopFrpc(env *C.JNIEnv, clazz C.jclass) {
	frpcMu.Lock()
	if frpcCancel != nil {
		frpcCancel()
		frpcCancel = nil
	}
	if frpcSvr != nil {
		frpcSvr.Close()
	}
	frpcMu.Unlock()
}

//export Java_frpwrapper_Frpwrapper_isFrpsRunning
func Java_frpwrapper_Frpwrapper_isFrpsRunning(env *C.JNIEnv, clazz C.jclass) C.jboolean {
	frpsMu.Lock()
	defer frpsMu.Unlock()
	if frpsRunning { return C.JNI_TRUE }
	return C.JNI_FALSE
}

//export Java_frpwrapper_Frpwrapper_isFrpcRunning
func Java_frpwrapper_Frpwrapper_isFrpcRunning(env *C.JNIEnv, clazz C.jclass) C.jboolean {
	frpcMu.Lock()
	defer frpcMu.Unlock()
	if frpcRunning { return C.JNI_TRUE }
	return C.JNI_FALSE
}

//export Java_frpwrapper_Frpwrapper_checkPort
func Java_frpwrapper_Frpwrapper_checkPort(env *C.JNIEnv, clazz C.jclass, port C.jint) C.jboolean {
	address := fmt.Sprintf("127.0.0.1:%d", int(port))
	conn, err := net.DialTimeout("tcp", address, 200*time.Millisecond)
	if err != nil { return C.JNI_FALSE }
	conn.Close()
	return C.JNI_TRUE
}

func main() {}
