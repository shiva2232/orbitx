package com.shiva2232.orbitx

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

private const val CHANNEL_ID = "vpn_channel"
private const val NOTIFICATION_ID = 1
private const val TAG = "HomeVpnService"

class HomeVpnService : VpnService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO)
    private var tunFd: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OrbitX VPN")
            .setContentText("VPN service is active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        val action = intent?.action
        if (action == "START_VPN") {
            val uuid = intent.getStringExtra("pairingHash") ?: ""
            val role = intent.getStringExtra("role") ?: ""
            val secret = intent.getStringExtra("presharedSecret") ?: ""
            
            Log.d(TAG, "START_VPN action received: uuid=$uuid, role=$role")
            startTunnel(uuid, role, secret)
        } else if (action == "STOP_VPN") {
            stopTunnel()
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "VPN Service Channel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun startTunnel(uuid: String, role: String, secret: String) {
        serviceScope.launch {
            try {
                // 1. Establish TUN interface
                val builder = Builder()
                    .setSession("OrbitX")
                    .setMtu(1420)
                    .addAddress("10.0.0.2", 32)
                    .addRoute("0.0.0.0", 0)

                val pfd = builder.establish() ?: error("VPN establish() failed")
                tunFd = pfd

                // 2. Submit FD to native engine via VpnBridge
                val fd = pfd.fd
                Log.i(TAG, "Submitting FD $fd to VpnBridge")
                
                // Wrap native calls in Throwable catch to prevent process termination on JNI error
                try {
                    VpnBridge.submitTunFd(fd)
                    VpnBridge.startEngine(uuid, role, secret)
                    Log.i(TAG, "VpnBridge engine started successfully")
                } catch (t: Throwable) {
                    Log.e(TAG, "Native VpnBridge call failed", t)
                    stopSelf()
                }

            } catch (e: Exception) {
                Log.e(TAG, "Failed to start tunnel", e)
                stopSelf()
            }
        }
    }

    private fun stopTunnel() {
        serviceScope.launch {
            try {
                VpnBridge.stopEngine()
                tunFd?.close()
                tunFd = null
                Log.i(TAG, "VPN stopped")
            } catch (t: Throwable) {
                Log.e(TAG, "Error stopping native engine", t)
            } finally {
                stopSelf()
            }
        }
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        stopTunnel()
    }

    companion object {
        private var instance: HomeVpnService? = null

        /**
         * This method is called by the Go native code (vpnengine.go) 
         * via ProtectSocketFdC to exclude its own traffic from the tunnel.
         */
        @JvmStatic
        fun protectSocketFromNative(fd: Int): Boolean {
            val res = instance?.protect(fd) ?: false
            if (!res) Log.w(TAG, "Socket protection failed for fd: $fd")
            return res
        }
    }
}
