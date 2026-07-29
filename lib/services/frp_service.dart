import 'package:flutter/services.dart';

class FrpService {
  static const MethodChannel _channel = MethodChannel('com.home.vpn/permission');

  /// Starts FRP Server with TOML configuration string
  static Future<String> startFrps(String configContent) async {
    try {
      final String? result = await _channel.invokeMethod('startFrps', {
        'config': configContent,
      });
      return result ?? "Success";
    } on PlatformException catch (e) {
      throw 'Failed to start FRPS: ${e.message}';
    }
  }

  /// Starts FRP Client with TOML configuration string
  static Future<String> startFrpc(String configContent) async {
    try {
      final String? result = await _channel.invokeMethod('startFrpc', {
        'config': configContent,
      });
      return result ?? "Success";
    } on PlatformException catch (e) {
      throw 'Failed to start FRPC: ${e.message}';
    }
  }

  static Future<String> stopFrps() async {
    try {
      final String? result = await _channel.invokeMethod('stopFrps');
      return result ?? "Success";
    } on PlatformException catch (e) {
      throw 'Failed to stop FRPS: ${e.message}';
    }
  }

  static Future<String> stopFrpc() async {
    try {
      final String? result = await _channel.invokeMethod('stopFrpc');
      return result ?? "Success";
    } on PlatformException catch (e) {
      throw 'Failed to stop FRPC: ${e.message}';
    }
  }
}