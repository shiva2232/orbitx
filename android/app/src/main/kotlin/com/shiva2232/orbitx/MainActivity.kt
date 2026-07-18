package com.shiva2232.orbitx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val scope = MainScope()
    private lateinit var methodChannel: MethodChannel
    private var pendingPermissionResult: MethodChannel.Result? = null
    
    // Move KeyUtils to a member variable to prevent garbage collection
    private lateinit var keyUtils: KeyUtils

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val filter1 = IntentFilter(TUN_READY_ACTION)
        val filter2 = IntentFilter(CONNECTION_ESTABLISHED_ACTION)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(tunReadyReceiver, filter1, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(connectionReceiver, filter2, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(tunReadyReceiver, filter1)
            registerReceiver(connectionReceiver, filter2)
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
                    pendingPermissionResult = result
                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        startActivityForResult(prepare, 1002)
                    } else {
                        startHomeService(call.arguments as? Map<*, *>)
                        pendingPermissionResult?.success(true)
                        pendingPermissionResult = null
                    }
                }
                "stopService" -> {
                    stopService(Intent(this, HomeVpnService::class.java))
                    result.success(true)
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
                pendingPermissionResult?.success(true)
            } else {
                pendingPermissionResult?.success(false)
            }
            pendingPermissionResult = null
        }
    }

    private fun startHomeService(args: Map<*, *>?) {
        val intent = Intent(this, HomeVpnService::class.java).apply {
            putExtra("pairingHash", args?.get("pairingHash") as? String)
            putExtra("role", args?.get("role") as? String)
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
