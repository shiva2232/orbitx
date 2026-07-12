package com.shiva2232.orbitx

object VpnBridge {
    init {
        try {
            System.loadLibrary("vpnengine")
        } catch (e: UnsatisfiedLinkError) {
            // Library may not be present during debug/build steps; swallow to avoid crash.
            e.printStackTrace()
        }
    }

    external fun submitTunFd(fd: Int): Int
    external fun startEngine(pairingHash: String, role: String, presharedSecret: String): Int
    external fun notifyNetworkChanged(): Int
}
