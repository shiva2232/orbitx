package com.shiva2232.orbitx

import android.os.Build
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.home.vpn/permission"
    private var pendingPairingHash: String? = null
    private var pendingRole: String? = null
    private var pendingSecret: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private lateinit var methodChannel: MethodChannel

    private val TUN_READY_ACTION = "com.shiva2232.orbitx.TUN_READY"
    private val CONNECTION_ESTABLISHED_ACTION = "com.shiva2232.orbitx.CONNECTION_ESTABLISHED"

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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) { // API 33+
            registerReceiver(tunReadyReceiver, IntentFilter(TUN_READY_ACTION), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(connectionReceiver, IntentFilter(CONNECTION_ESTABLISHED_ACTION), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(tunReadyReceiver, IntentFilter(TUN_READY_ACTION))
            registerReceiver(connectionReceiver, IntentFilter(CONNECTION_ESTABLISHED_ACTION))
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
                    val args = call.arguments as? Map<String, Any>
                    pendingPairingHash = args?.get("pairingHash") as? String
                    pendingRole = args?.get("role") as? String
                    pendingSecret = args?.get("presharedSecret") as? String
                    pendingPermissionResult = result

                    val prepare = VpnService.prepare(this)
                    if (prepare != null) {
                        startActivityForResult(prepare, 1002)
                    } else {
                        startHomeService()
                        pendingPermissionResult?.success(true)
                        pendingPermissionResult = null
                    }
                }
                "addAllowedApp" -> {
                    val args = call.arguments as? Map<String, Any>
                    val pkg = args?.get("packageName") as? String
                    if (pkg != null) {
                        val intent = Intent(this, HomeVpnService::class.java)
                        intent.action = "com.shiva2232.orbitx.ACTION_ADD_ALLOWED_APP"
                        intent.putExtra("packageName", pkg)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } else {
                        result.error("NO_PKG", "packageName missing", null)
                    }
                }
                "removeAllowedApp" -> {
                    val args = call.arguments as? Map<String, Any>
                    val pkg = args?.get("packageName") as? String
                    if (pkg != null) {
                        val intent = Intent(this, HomeVpnService::class.java)
                        intent.action = "com.shiva2232.orbitx.ACTION_REMOVE_ALLOWED_APP"
                        intent.putExtra("packageName", pkg)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } else {
                        result.error("NO_PKG", "packageName missing", null)
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
        try {
            unregisterReceiver(tunReadyReceiver)
        } catch (e: Exception) {
            // ignore
        }
        try {
            unregisterReceiver(connectionReceiver)
        } catch (e: Exception) {
            // ignore
        }
    }

    private fun showTunnelConnectedToast() {
        Toast.makeText(this, "Connected over tunnel", Toast.LENGTH_SHORT).show()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1002) {
            if (resultCode == Activity.RESULT_OK) {
                startHomeService()
                pendingPermissionResult?.success(true)
            } else {
                pendingPermissionResult?.success(false)
            }
            pendingPermissionResult = null
        }
    }

    private fun startHomeService() {
        val intent = Intent(this, HomeVpnService::class.java)
        intent.putExtra("pairingHash", pendingPairingHash)
        intent.putExtra("role", pendingRole)
        intent.putExtra("presharedSecret", pendingSecret)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
