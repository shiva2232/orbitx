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

    @JvmStatic
    external fun submitTunFd(fd: Int): Int
    @JvmStatic
    external fun startEngine(pairingHash: String, role: String, presharedSecret: String): Int
    @JvmStatic
    external fun stopEngine(): Int
    @JvmStatic
    external fun notifyNetworkChanged(): Int
    @JvmStatic
    external fun getStatusJSON(): String?
}
