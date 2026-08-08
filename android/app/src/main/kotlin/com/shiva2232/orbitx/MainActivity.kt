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
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private val scope = MainScope()
    private lateinit var methodChannel: MethodChannel
    private var pendingPermissionResult: MethodChannel.Result? = null
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

    private lateinit var connectivityManager: ConnectivityManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize FRP Native with a writable directory for TOML configs
        try {
            Frpwrapper.init(cacheDir.absolutePath)
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to initialize FRP Native: ${e.message}")
        }

        // lockscreen activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        
        handleLockscreenIntent(intent)
        // above lock screen activity
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

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

        // This triggers when the app is already open/running in the background
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLockscreenIntent(intent)
        
        // Tell Flutter to navigate to the new initial route if the engine is already warm
        if (intent.getBooleanExtra("launched_from_lockscreen", false)) {
            flutterEngine?.navigationChannel?.pushRoute("/lockscreen")
        }
    }

    private fun handleLockscreenIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("launched_from_lockscreen", false) == true) {
            intent.putExtra("route", "/lockscreen")
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
                    if (config != null) {
                        Frpwrapper.startFrps(config) // Go backgrounds this automatically
                        result.success("FRPS Starting")
                    } else result.error("ARG_ERR", "Config missing", null)
                }
                "stopFrps" -> {
                    Frpwrapper.stopFrps()
                    result.success("FRPS Stopped")
                }
                "startFrpc" -> {
                    val config = call.argument<String>("config")
                    if (config != null) {
                        Frpwrapper.startFrpc(config)
                        result.success("FRPC Starting")
                    } else result.error("ARG_ERR", "Config missing", null)
                }
                "stopFrpc" -> {
                    Frpwrapper.stopFrpc()
                    result.success("FRPC Stopped")
                }
                "isFrpsRunning" -> result.success(Frpwrapper.isFrpsRunning())
                "isFrpcRunning" -> result.success(Frpwrapper.isFrpcRunning())
                "checkPort" -> {
                    val port = call.argument<Int>("port") ?: 0
                    result.success(Frpwrapper.checkPort(port))
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
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
