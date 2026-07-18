package com.shiva2232.orbitx


import android.content.Intent
import android.net.VpnService
import com.wireguard.android.backend.Backend
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch


private const val CONNECTION_ESTABLISHED_ACTION = "com.shiva2232.orbitx.CONNECTION_ESTABLISHED"
private const val TUN_READY_ACTION = "com.shiva2232.orbitx.TUN_READY"

class HomeVpnService : VpnService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO)
    private lateinit var backend: Backend

    // Define a concrete Tunnel object
    private val myTunnel = object : Tunnel {
        override fun getName(): String = "WireGuardTunnel"
        override fun onStateChange(state: Tunnel.State) {
            // Handle connection state changes here (e.g. UP, DOWN)
        }
    }

    override fun onCreate() {
        super.onCreate()
        // Instantiate the official userspace WireGuard backend
        backend = GoBackend(applicationContext)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == "START_VPN") {
            val configText = intent.getStringExtra("CONFIG_TEXT") ?: ""
            startTunnel(configText)
        } else if (action == "STOP_VPN") {
            stopTunnel()
        }

        return START_NOT_STICKY
    }

    private fun startTunnel(configText: String) {
        serviceScope.launch {
            try {
                // Parse configuration string directly into the official Config object
                val config = Config.parse(configText.byteInputStream())

                // Bring the tunnel interface UP
                backend.setState(myTunnel, Tunnel.State.UP, config)
            } catch (e: Exception) {
                e.printStackTrace()
                stopSelf()
            }
        }
    }

    private fun stopTunnel() {
        serviceScope.launch {
            try {
                // Safely take down the tunnel
                backend.setState(myTunnel, Tunnel.State.DOWN, null)
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                stopSelf()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopTunnel()
    }
}
