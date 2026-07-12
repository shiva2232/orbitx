package com.shiva2232.orbitx

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log

class NetworkChangeReceiver : ConnectivityManager.NetworkCallback() {
    override fun onAvailable(network: Network) {
        super.onAvailable(network)
        try {
            VpnBridge.notifyNetworkChanged()
        } catch (e: Throwable) {
            Log.e("NetworkChangeReceiver", "notifyNetworkChanged failed", e)
        }
    }

    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
        super.onCapabilitiesChanged(network, networkCapabilities)
        try {
            VpnBridge.notifyNetworkChanged()
        } catch (e: Throwable) {
            Log.e("NetworkChangeReceiver", "notifyNetworkChanged failed", e)
        }
    }
}
