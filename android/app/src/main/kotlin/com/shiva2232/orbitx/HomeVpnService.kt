package com.shiva2232.orbitx

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

private const val CHANNEL_ID = "vpn_channel"
private const val NOTIFICATION_ID = 1
private const val TAG = "HomeVpnService"

class HomeVpnService : VpnService() {

    private val serviceScope = CoroutineScope(Dispatchers.IO)
    private var tunnelJob: Job? = null
    private var statusJob: Job? = null
    private var activeTunFd: Int = -1
    private val networkCallback = NetworkChangeReceiver()

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate")
        instance = this
        createNotificationChannel()
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.registerDefaultNetworkCallback(networkCallback)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register network callback", e)
        }
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
        Log.d(TAG, "onStartCommand: action=$action")

        if (action == "START_VPN") {
            val uuid = intent.getStringExtra("pairingHash") ?: ""
            val role = intent.getStringExtra("role") ?: ""
            val secret = intent.getStringExtra("presharedSecret") ?: ""
            
            // Cancel any pending startup or status observation from a previous session
            tunnelJob?.cancel()
            statusJob?.cancel()
            
            tunnelJob = serviceScope.launch {
                startTunnel(uuid, role, secret)
            }
        } else if (action == "STOP_VPN") {
            cleanupResources()
            stopSelf()
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

    private suspend fun startTunnel(uuid: String, role: String, secret: String) {
        try {
            // Clean up native resources before re-starting to prevent conflicts
            cleanupNativeOnly()

            // Determine internal IP and normalize role
            val isMaster = role.equals("master", ignoreCase = true) || role.equals("host", ignoreCase = true)
            val internalIp = if (isMaster) "10.0.0.1" else "10.0.0.2"
            val normalizedRole = if (isMaster) "master" else "slave"

            Log.i(TAG, "Starting tunnel with IP $internalIp as $normalizedRole")

            // 1. Establish TUN interface
            val builder = Builder()
                .setSession("OrbitX")
                .setMtu(1280)
                .addAddress(internalIp, 24)
                .addRoute("10.0.0.0", 24)
                .addDnsServer("1.1.1.1")
                .addDisallowedApplication(packageName)

            val pfd = builder.establish() ?: error("VPN establish() failed")
            
            // 2. Transfer ownership to native code. 
            // detachedFd MUST be closed by the receiver (Go engine).
            // We do NOT adopt it back into a ParcelFileDescriptor here to avoid fdsan double-ownership crashes.
            val fd = pfd.detachFd()
            activeTunFd = fd

            Log.i(TAG, "TUN FD detached: $fd. Submitting to VpnBridge...")
            
            try {
                // Initialize JNI references and submit FD
                VpnBridge.submitTunFd(fd)
                // Start the engine
                VpnBridge.startEngine(uuid, normalizedRole, secret)
                
                sendBroadcast(Intent("com.shiva2232.orbitx.TUN_READY").setPackage(packageName))
                observeEngineStatus()
                Log.i(TAG, "Native engine started successfully")
            } catch (t: Throwable) {
                Log.e(TAG, "Native engine startup failed", t)
                // If native side failed to take ownership, close it now manually to avoid leak
                closeRawFd(fd)
                cleanupResources()
                stopSelf()
            }

        } catch (e: Exception) {
            Log.e(TAG, "Critical failure during tunnel establishment", e)
            cleanupResources()
            stopSelf()
        }
    }

    private fun observeEngineStatus() {
        statusJob?.cancel()
        statusJob = serviceScope.launch {
            var lastEndpoint = ""
            while (isActive && activeTunFd != -1) {
                try {
                    val status = VpnBridge.getStatusJSON().orEmpty()
                    if (status.contains("\"state\":\"CONNECTED\"")) {
                        val endpoint = status.substringAfter("\"peerIp\":\"").substringBefore('"') + ":" +
                            status.substringAfter("\"peerPort\":").takeWhile { it.isDigit() }
                        if (endpoint != ":" && endpoint != lastEndpoint) {
                            lastEndpoint = endpoint
                            val parts = endpoint.split(":")
                            sendBroadcast(Intent("com.shiva2232.orbitx.CONNECTION_ESTABLISHED")
                                .setPackage(packageName)
                                .putExtra("peerIp", parts.first())
                                .putExtra("peerPort", parts.last().toIntOrNull() ?: 0))
                        }
                    }
                } catch (e: Throwable) {}
                delay(1000)
            }
        }
    }

    private fun cleanupNativeOnly() {
        synchronized(this) {
            try {
                VpnBridge.stopEngine() // This is expected to call native close() on the FD
            } catch (t: Throwable) {
                Log.w(TAG, "Error stopping native engine", t)
            }
            activeTunFd = -1
        }
    }

    private fun cleanupResources() {
        tunnelJob?.cancel()
        statusJob?.cancel()
        cleanupNativeOnly()
    }

    private fun closeRawFd(fd: Int) {
        if (fd != -1) {
            try {
                // Temporary adoption just to close it
                ParcelFileDescriptor.adoptFd(fd).close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing raw FD $fd", e)
            }
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        instance = null
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(networkCallback)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister network callback", e)
        }
        cleanupResources()
        super.onDestroy()
    }

    companion object {
        private var instance: HomeVpnService? = null

        @JvmStatic
        fun protectSocketFromNative(fd: Int): Boolean {
            val res = instance?.protect(fd) ?: false
            if (!res) Log.w(TAG, "protectSocketFromNative: Socket protection failed for fd: $fd")
            return res
        }
    }
}
