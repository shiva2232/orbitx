import 'dart:async';
import 'package:flutter/services.dart';
import 'vpn_engine_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnController {
  static const _platform = MethodChannel('com.home.vpn/permission');

  final StreamController<Map<String, dynamic>> _statusController = StreamController.broadcast();
  final Set<String> _allowed = {};

  VpnController() {
    // listen for tunReady calls from Android
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'tunReady') {
        _statusController.add({'event': 'tunReady'});
      }
    });
    _loadAllowedApps();
  }

  Future<void> _loadAllowedApps() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList('vpn_allowed_apps') ?? [];
      _allowed.clear();
      _allowed.addAll(list);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _saveAllowedApps() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('vpn_allowed_apps', _allowed.toList());
    } catch (e) {
      // ignore
    }
  }

  Future<bool> requestPermissionAndStart(String pairingHash, String role, String preshared) async {
    final ok = await _platform.invokeMethod('requestPermission', {
      'pairingHash': pairingHash,
      'role': role,
      'presharedSecret': preshared,
    });
    return ok == true;
  }

  Future<bool> addAllowedApp(String packageName) async {
    try {
      final ok = await _platform.invokeMethod('addAllowedApp', {'packageName': packageName});
      if (ok == true) {
        _allowed.add(packageName);
        await _saveAllowedApps();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeAllowedApp(String packageName) async {
    try {
      final ok = await _platform.invokeMethod('removeAllowedApp', {'packageName': packageName});
      if (ok == true) {
        _allowed.remove(packageName);
        await _saveAllowedApps();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> stopService() async {
    await _platform.invokeMethod('stopService');
    stopEngine();
  }

  // FFI wrappers
  int startEngineViaFFI(String pairingHash, String role, String preshared) {
    return startEngine(pairingHash, role, preshared);
  }

  int stopEngine() => stopEngineWrapper();

  Stream<Map<String, dynamic>> get events => _statusController.stream;

  bool isAllowed(String packageName) => _allowed.contains(packageName);

}

// helper to expose stopEngine name consistent with FFI file
int stopEngineWrapper() => stopEngine();
