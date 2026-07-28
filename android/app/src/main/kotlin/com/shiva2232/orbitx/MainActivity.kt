package com.shiva2232.orbitx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import frpwrapper.Frpwrapper
import kotlin.concurrent.thread
import kotlinx.coroutines.cancel

class MainActivity : FlutterActivity() {
    private val scope = MainScope()
    private lateinit var methodChannel: MethodChannel
    private var pendingPermissionResult: MethodChannel.Result? = null
    
    // Store VPN arguments in a member variable to avoid losing them
    private var pendingVpnArgs: Map<*, *>? = null

    private val tunReadyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            methodChannel.invokeMethod("tunReady", null)
        }
    }

    private val connectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val peerIp = intent?.getStringExtra("peerIp")
            val peerPort = intent?.getIntExtra("peerPort", 0) ?: 0
            methodChannel.invokeMethod(
                "connectionEstablished",
                mapOf("peerIp" to peerIp, "peerPort" to peerPort),
            )
            showTunnelConnectedToast()
        }
    }

    // use sim only
    private lateinit var connectivityManager: ConnectivityManager
    private var cellularNetworkCallback: ConnectivityManager.NetworkCallback? = null


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        // forceCellularNetwork()
        try {
            // Seq.setContext(this)
        } catch (e: Exception) {
            Log.w("TAG", "Gomobile Seq context not initialized")
        }

        val filter1 = IntentFilter(TUN_READY_ACTION)
        val filter2 = IntentFilter(CONNECTION_ESTABLISHED_ACTION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(tunReadyReceiver, filter1, RECEIVER_NOT_EXPORTED)
            registerReceiver(connectionReceiver, filter2, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(tunReadyReceiver, filter1)
            registerReceiver(connectionReceiver, filter2)
        }
    }


    private fun forceCellularNetwork() {
        // 1. Build a request specifically for Cellular/Mobile data
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        // 2. Define the callback to handle the network once found
        cellularNetworkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                Log.d("NetworkManager", "Cellular network is available.")

                // 3. Bind the application process to this cellular network
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val result = connectivityManager.bindProcessToNetwork(network)
                    Log.d("NetworkManager", "Process bound to Cellular: $result")
                } else {
                    // Fallback for older API versions (deprecated in API 23)
                    @Suppress("DEPRECATION")
                    ConnectivityManager.setProcessDefaultNetwork(network)
                }
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                Log.d("NetworkManager", "Cellular network lost.")
                // Unbind if cellular goes away, reverting to system default (Wi-Fi)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    connectivityManager.bindProcessToNetwork(null)
                } else {
                    @Suppress("DEPRECATION")
                    ConnectivityManager.setProcessDefaultNetwork(null)
                }
            }
        }

        // 4. Request the network from the system
        cellularNetworkCallback?.let { callback ->
            connectivityManager.requestNetwork(request, callback)
        }
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (pendingPermissionResult != null) {
                        result.error("ALREADY_PENDING", "VPN permission request already in progress", null)
                        return@setMethodCallHandler
                    }
                    
                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        pendingPermissionResult = result
                        pendingVpnArgs = call.arguments as? Map<*, *>
                        startActivityForResult(prepare, 1002)
                    } else {
                        startHomeService(call.arguments as? Map<*, *>)
                        result.success(true)
                    }
                }
                "stopService" -> {
                    stopService(Intent(this, HomeVpnService::class.java))
                    result.success(true)
                }
                "startFrps" -> {
                    val config = call.argument<String>("config")
                    if (config == null) {
                        result.error("INVALID_ARGUMENT", "Config content is required", null)
                        return@setMethodCallHandler
                    }

                    // Run in a background thread as FRP blocks
                    thread {
                        try {
                            Frpwrapper.startFrps(config)
                            // Note: startFrps blocks until stopped
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                    result.success("FRPS Started")
                }
                "stopFrps" -> {
                    thread {
                        try {
                            Frpwrapper.stopFrps()
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                    result.success("FRPS Stopped")
                }
                "startFrpc" -> {
                    val config = call.argument<String>("config")
                    if (config == null) {
                        result.error("INVALID_ARGUMENT", "Config content is required", null)
                        return@setMethodCallHandler
                    }

                    thread {
                        try {
                            Frpwrapper.startFrpc(config)
                            // Note: startFrpc blocks until stopped
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                    result.success("FRPC Started")
                }
                "stopFrpc" -> {
                    thread {
                        try {
                            Frpwrapper.stopFrpc()
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                    result.success("FRPC Stopped")
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        cellularNetworkCallback?.let { callback ->
            connectivityManager.unregisterNetworkCallback(callback)
        }
        scope.cancel()
        try { unregisterReceiver(tunReadyReceiver) } catch (e: Exception) {}
        try { unregisterReceiver(connectionReceiver) } catch (e: Exception) {}
    }

    private fun showTunnelConnectedToast() {
        Toast.makeText(this, "Connected over tunnel", Toast.LENGTH_SHORT).show()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1002) {
            if (resultCode == RESULT_OK) {
                startHomeService(pendingVpnArgs)
                pendingPermissionResult?.success(true)
            } else {
                pendingPermissionResult?.success(false)
            }
            pendingPermissionResult = null
            pendingVpnArgs = null
        }
    }

    private fun startHomeService(args: Map<*, *>?) {
        val intent = Intent(this, HomeVpnService::class.java).apply {
            action = "START_VPN"
            putExtra("pairingHash", args?.get("pairingHash") as? String)
            putExtra("role", args?.get("role") as? String)
            putExtra("deviceName", args?.get("deviceName") as? String)
            putExtra("presharedSecret", args?.get("presharedSecret") as? String)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val CHANNEL = "com.home.vpn/permission"
        private const val TUN_READY_ACTION = "com.shiva2232.orbitx.TUN_READY"
        private const val CONNECTION_ESTABLISHED_ACTION = "com.shiva2232.orbitx.CONNECTION_ESTABLISHED"
    }
}
