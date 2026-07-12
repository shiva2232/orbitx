package com.shiva2232.orbitx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import org.json.JSONObject

private const val CONNECTION_ESTABLISHED_ACTION = "com.shiva2232.orbitx.CONNECTION_ESTABLISHED"
private const val TUN_READY_ACTION = "com.shiva2232.orbitx.TUN_READY"

class HomeVpnService : VpnService() {
    private var pfd: ParcelFileDescriptor? = null
    private val allowedApps = mutableSetOf<String>()
    private var statusHandler: Handler? = null
    private var currentConnected = false
    private var currentRole = "master"

    override fun onBind(intent: Intent?): IBinder? {
        return super.onBind(intent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()

        val pairingHash = intent?.getStringExtra("pairingHash")
        val role = intent?.getStringExtra("role")
        val preshared = intent?.getStringExtra("presharedSecret")
        if (!role.isNullOrBlank()) {
            currentRole = role
        }

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

        pfd = establishTunnel(currentRole)
        pfd?.let {
            val tunReadyIntent = Intent(TUN_READY_ACTION).setPackage(packageName)
            sendBroadcast(tunReadyIntent)

            // Keep ParcelFileDescriptor alive and handoff raw fd to native engine
            try {
                VpnBridge.submitTunFd(it.fd)
                if (!pairingHash.isNullOrBlank() && !role.isNullOrBlank()) {
                    VpnBridge.startEngine(pairingHash, role, preshared ?: "")
                    startStatusPolling()
                }
            } catch (e: Throwable) {
                e.printStackTrace()
            }
        }

        return START_STICKY
    }

    fun establishTunnel(role: String = currentRole): ParcelFileDescriptor? {
        val builder = Builder()
        if (role.equals("slave", ignoreCase = true)) {
            builder.addAddress("10.99.0.2", 32)
            builder.addRoute("10.99.0.1", 32)
        } else {
            builder.addAddress("10.99.0.1", 32)
            builder.addRoute("10.99.0.2", 32)
        }
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
        pfd = establishTunnel(currentRole)
        pfd?.let {
            val intent = Intent(TUN_READY_ACTION).setPackage(packageName)
            sendBroadcast(intent)

            try {
                VpnBridge.submitTunFd(it.fd)
            } catch (e: Throwable) {
                e.printStackTrace()
            }
        }
    }

    private fun sendConnectionBroadcast(peerIp: String? = null, peerPort: Int = 0) {
        val connectedIntent = Intent(CONNECTION_ESTABLISHED_ACTION).setPackage(packageName)
        if (!peerIp.isNullOrBlank()) {
            connectedIntent.putExtra("peerIp", peerIp)
        }
        if (peerPort > 0) {
            connectedIntent.putExtra("peerPort", peerPort)
        }
        sendBroadcast(connectedIntent)
    }

    private val statusCheckRunnable = object : Runnable {
        override fun run() {
            try {
                val statusJson = VpnBridge.getStatusJSON()
                if (!statusJson.isNullOrBlank()) {
                    val json = JSONObject(statusJson)
                    val state = json.optString("state", "")
                    val peerIp = json.optString("peerIp", "").takeIf { it.isNotBlank() }
                    val peerPort = json.optInt("peerPort", 0)
                    if (state == "CONNECTED" && !currentConnected) {
                        currentConnected = true
                        sendConnectionBroadcast(peerIp, peerPort)
                    } else if (state != "CONNECTED") {
                        currentConnected = false
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                statusHandler?.postDelayed(this, 1000)
            }
        }
    }

    private fun startStatusPolling() {
        if (statusHandler == null) {
            statusHandler = Handler(Looper.getMainLooper())
        }
        statusHandler?.removeCallbacks(statusCheckRunnable)
        statusHandler?.post(statusCheckRunnable)
    }

    private fun stopStatusPolling() {
        statusHandler?.removeCallbacks(statusCheckRunnable)
        statusHandler = null
        currentConnected = false
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
        stopStatusPolling()
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
