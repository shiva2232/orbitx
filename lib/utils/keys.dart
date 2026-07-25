import 'dart:async';
import 'package:flutter/services.dart';
import 'package:orbitx/utils/device_info.dart';

class KeyUtils {
  static const _channel = MethodChannel('com.home.vpn/permission');
  
  String _deviceName = '';
  final bool isHost;
  String? _uuid;

  KeyUtils(this.isHost) {
    _initDeviceName();
  }

  Future<void> _initDeviceName() async {
    _deviceName = await DeviceService.getDeviceName();
  }

  Future<bool> init() async {
    return true;
  }

  /// Starts the VPN. The role is normalized to 'master' or 'slave'
  /// to match the native engine's expectations.
  Future<void> startVPN(String uuid, {String secret = "orbitx_p2p_default_secret"}) async {
    _uuid = uuid;
    if (_deviceName.isEmpty) {
      await _initDeviceName();
    }

    try {
      await _channel.invokeMethod('requestPermission', {
        'pairingHash': _uuid,
        'role': isHost ? 'master' : 'slave',
        'deviceName': _deviceName,
        'presharedSecret': secret,
      });
    } on PlatformException catch (e) {
      print("VPN Start Error: ${e.message}");
    }
  }

  Future<void> rerun() async {
    if (_uuid != null) {
      await startVPN(_uuid!);
    }
  }

  Future<bool> pair(String uuid) async {
    _uuid = uuid;
    await startVPN(uuid);
    return true;
  }

  Future<void> destroy() async {
    try {
      await _channel.invokeMethod('stopService');
    } on PlatformException catch (e) {
      print("VPN Stop Error: ${e.message}");
    }
  }
}
