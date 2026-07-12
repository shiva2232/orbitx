package com.shiva2232.orbitx

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.home.vpn/permission"
	private var pendingPairingHash: String? = null
	private var pendingRole: String? = null
	private var pendingSecret: String? = null

	private val TUN_READY_ACTION = "com.shiva2232.orbitx.TUN_READY"

	private val tunReadyReceiver = object : BroadcastReceiver() {
		override fun onReceive(context: Context?, intent: Intent?) {
			// forward to Flutter via MethodChannel
			MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, CHANNEL).invokeMethod("tunReady", null)
		}
	}

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)

		MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"requestPermission" -> {
					val args = call.arguments as? Map<String, Any>
					pendingPairingHash = args?.get("pairingHash") as? String
					pendingRole = args?.get("role") as? String
					pendingSecret = args?.get("presharedSecret") as? String

					val prepare = VpnService.prepare(this)
					if (prepare != null) {
						startActivityForResult(prepare, 1002)
						result.success(true)
					} else {
						// already prepared
						startHomeService()
						result.success(true)
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

		// register local broadcast for TUN ready
		registerReceiver(tunReadyReceiver, IntentFilter(TUN_READY_ACTION))
	}

	override fun onDestroy() {
		super.onDestroy()
		try {
			unregisterReceiver(tunReadyReceiver)
		} catch (e: Exception) {
			// ignore
		}
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == 1002) {
			if (resultCode == Activity.RESULT_OK) {
				startHomeService()
			}
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
