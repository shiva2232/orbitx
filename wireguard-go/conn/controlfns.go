/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2017-2025 WireGuard LLC. All Rights Reserved.
 */

package conn

import (
	"net"
	"syscall"
)

const socketBufferSize = 7 << 20

type ControlFn func(network, address string, c syscall.RawConn) error

var controlFns = []ControlFn{}

// RegisterControlFn allows external packages to add socket configuration logic.
// This is used on Android to call VpnService.protect().
func RegisterControlFn(fn ControlFn) {
	controlFns = append(controlFns, fn)
}

func listenConfig() *net.ListenConfig {
	return &net.ListenConfig{
		Control: func(network, address string, c syscall.RawConn) error {
			for _, fn := range controlFns {
				if err := fn(network, address, c); err != nil {
					return err
				}
			}
			return nil
		},
	}
}
