// ZalupaGram fork: Xray-core inside the app, as a C library. The app gives
// a JSON config with a local SOCKS5 inbound, Telegram connects through it.
// Built by build_ios.sh into ZGXray.xcframework (a static library).
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"runtime/debug"
	"strings"
	"sync"
	"unsafe"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
	"github.com/xtls/xray-core/infra/conf/serial"
)

var (
	lock     sync.Mutex
	instance *core.Instance
)

func stopLocked() {
	if instance != nil {
		instance.Close()
		instance = nil
	}
}

// Starts Xray with the config, stopping the running one first.
// Returns NULL on success or an error text to free with ZGXrayFree.
//
//export ZGXrayStart
func ZGXrayStart(config *C.char) *C.char {
	lock.Lock()
	defer lock.Unlock()
	stopLocked()
	// The app shares its memory with the rest of Telegram.
	debug.SetGCPercent(50)
	parsed, err := serial.LoadJSONConfig(strings.NewReader(C.GoString(config)))
	if err != nil {
		return C.CString(err.Error())
	}
	server, err := core.New(parsed)
	if err != nil {
		return C.CString(err.Error())
	}
	if err := server.Start(); err != nil {
		server.Close()
		return C.CString(err.Error())
	}
	instance = server
	return nil
}

//export ZGXrayStop
func ZGXrayStop() {
	lock.Lock()
	defer lock.Unlock()
	stopLocked()
}

//export ZGXrayFree
func ZGXrayFree(value *C.char) {
	C.free(unsafe.Pointer(value))
}

func main() {}
