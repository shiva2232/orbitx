package com.shiva2232.orbitx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor

private const val CONNECTION_ESTABLISHED_ACTION = "com.shiva2232.orbitx.CONNECTION_ESTABLISHED"

class HomeVpnService : VpnService() {
    private var pfd: ParcelFileDescriptor? = null
    private val allowedApps = mutableSetOf<String>()

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()

        val pairingHash = intent?.getStringExtra("pairingHash")
        val role = intent?.getStringExtra("role")
        val preshared = intent?.getStringExtra("presharedSecret")

        // handle dynamic add allowed app action
        if (intent?.action == "com.shiva2232.orbitx.ACTION_ADD_ALLOWED_APP") {
            val pkg = intent.getStringExtra("packageName")
            if (!pkg.isNullOrEmpty()) {
                allowedApps.add(pkg)
                // re-establish tunnel to apply new allowed apps
                reestablishTunnelWithAllowedApps()
            }
            return START_STICKY
        }
        // handle dynamic remove allowed app action
        if (intent?.action == "com.shiva2232.orbitx.ACTION_REMOVE_ALLOWED_APP") {
            val pkg = intent.getStringExtra("packageName")
            if (!pkg.isNullOrEmpty()) {
                allowedApps.remove(pkg)
                reestablishTunnelWithAllowedApps()
            }
            return START_STICKY
        }

        pfd = establishTunnel()
        pfd?.let {
            // Keep ParcelFileDescriptor alive and handoff raw fd to native engine
            try {
                VpnBridge.submitTunFd(it.fd)
                if (!pairingHash.isNullOrBlank() && !role.isNullOrBlank()) {
                    VpnBridge.startEngine(pairingHash, role, preshared ?: "")
                }
                // notify Flutter/UI that TUN is ready
                val tunReadyIntent = Intent("com.shiva2232.orbitx.TUN_READY")
                sendBroadcast(tunReadyIntent)
                // notify local app that tunnel is connected
                sendConnectionBroadcast()
            } catch (e: Throwable) {
                e.printStackTrace()
            }
        }

        return START_STICKY
    }

    fun establishTunnel(): ParcelFileDescriptor? {
        val builder = Builder()
        builder.addAddress("10.99.0.1", 32)
        builder.setMtu(1400)
        configureSplitTunnel(builder, "192.168.50.0/24")
        // Restrict VPN to configured allowed apps so other apps keep using normal network
        try {
            if (allowedApps.isEmpty()) {
                allowedApps.add(applicationContext.packageName)
            }
            for (pkg in allowedApps) {
                try {
                    builder.addAllowedApplication(pkg)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return try {
            builder.establish()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun reestablishTunnelWithAllowedApps() {
        try {
            // close existing pfd
            pfd?.close()
        } catch (e: Exception) {
            e.printStackTrace()
        }
        // establish fresh
        pfd = establishTunnel()
        pfd?.let {
            try {
                VpnBridge.submitTunFd(it.fd)
                val intent = Intent("com.shiva2232.orbitx.TUN_READY")
                sendBroadcast(intent)
                sendConnectionBroadcast()
            } catch (e: Throwable) {
                e.printStackTrace()
            }
        }
    }

    private fun sendConnectionBroadcast() {
        val connectedIntent = Intent(CONNECTION_ESTABLISHED_ACTION)
        sendBroadcast(connectedIntent)
    }

    fun configureSplitTunnel(builder: Builder, subnetCidr: String) {
        // naive parse of cidr like 192.168.50.0/24
        val parts = subnetCidr.split("/")
        if (parts.size == 2) {
            val network = parts[0]
            val prefix = parts[1].toIntOrNull() ?: 24
            builder.addRoute(network, prefix)
        }
    }

    fun handoffTunFd(pfd: ParcelFileDescriptor) {
        this.pfd = pfd
        try {
            VpnBridge.submitTunFd(pfd.fd)
        } catch (e: Throwable) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        pfd?.close()
    }

    fun stopEngineAndService() {
        try {
            VpnBridge.notifyNetworkChanged() // best-effort
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        pfd?.close()
        stopForeground(true)
        stopSelf()
    }

    private fun startForegroundNotification() {
        val channelId = "home_vpn_channel"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "Home VPN", NotificationManager.IMPORTANCE_LOW)
            nm.createNotificationChannel(ch)
        }

        val notification = Notification.Builder(this, channelId)
            .setContentTitle("Home VPN")
            .setContentText("Connected")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .build()

        startForeground(12345, notification)
    }
}
