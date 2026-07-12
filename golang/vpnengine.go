package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/json"
	"os"
	"sync"
	"time"
	"unsafe"
)

var (
	mu       sync.Mutex
	tunFd    int
	ctx      context.Context
	cancelFn context.CancelFunc
	status   = map[string]interface{}{"state": "DISCONNECTED"}
)

//export SubmitTunFd
func SubmitTunFd(fd C.int) C.int {
	mu.Lock()
	defer mu.Unlock()
	if int(fd) <= 0 {
		return C.int(-1)
	}
	tunFd = int(fd)
	// keep a dummy os.File to avoid GC closing issues in some cases
	_ = os.NewFile(uintptr(fd), "tunfd")
	status["state"] = "TUN_READY"
	return 0
}

//export StartEngine
func StartEngine(cpair *C.char, crole *C.char, csecret *C.char) C.int {
	pair := C.GoString(cpair)
	role := C.GoString(crole)
	_ = C.GoString(csecret)

	mu.Lock()
	if tunFd == 0 {
		mu.Unlock()
		return C.int(-2) // fd missing
	}
	if cancelFn != nil {
		cancelFn()
	}
	ctx, cancelFn = context.WithCancel(context.Background())
	status["state"] = "CONNECTING"
	status["pair"] = pair
	status["role"] = role
	mu.Unlock()

	go engineLoop(ctx)
	return 0
}

func engineLoop(ctx context.Context) {
	// simple simulated engine: after 1s -> WAITING_PEER, 2s -> CONNECTED
	updateStatus(map[string]interface{}{"state": "WAITING_PEER"})
	select {
	case <-time.After(2 * time.Second):
		updateStatus(map[string]interface{}{"state": "CONNECTED", "peerIp": "203.0.113.5", "peerPort": 12345, "lastHandshakeMs": time.Now().UnixMilli()})
	case <-ctx.Done():
		updateStatus(map[string]interface{}{"state": "DISCONNECTED"})
		return
	}

	// heartbeat
	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			// noop
		case <-ctx.Done():
			updateStatus(map[string]interface{}{"state": "DISCONNECTED"})
			return
		}
	}
}

func updateStatus(m map[string]interface{}) {
	mu.Lock()
	defer mu.Unlock()
	for k, v := range m {
		status[k] = v
	}
}

//export StopEngine
func StopEngine() C.int {
	mu.Lock()
	if cancelFn != nil {
		cancelFn()
		cancelFn = nil
	}
	status = map[string]interface{}{"state": "DISCONNECTED"}
	mu.Unlock()
	return 0
}

//export NotifyNetworkChanged
func NotifyNetworkChanged() C.int {
	// kick an immediate refresh in a real implementation
	updateStatus(map[string]interface{}{"state": "RECONNECTING"})
	go func() {
		time.Sleep(500 * time.Millisecond)
		updateStatus(map[string]interface{}{"state": "CONNECTED", "lastHandshakeMs": time.Now().UnixMilli()})
	}()
	return 0
}

//export GetStatusJSON
func GetStatusJSON() *C.char {
	mu.Lock()
	b, _ := json.Marshal(status)
	mu.Unlock()
	return C.CString(string(b))
}

//export FreeCString
func FreeCString(ptr *C.char) {
	if ptr == nil {
		return
	}
	C.free(unsafe.Pointer(ptr))
}

func main() {}
