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
      await _channel.invokeMethod('stopFrps');
      return "Success";
    } on PlatformException catch (e) {
      throw 'Failed to stop FRPS: ${e.message}';
    }
  }

  static Future<String> stopFrpc() async {
    try {
      await _channel.invokeMethod('stopFrpc');
      return "Success";
    } on PlatformException catch (e) {
      throw 'Failed to stop FRPC: ${e.message}';
    }
  }

  static Future<bool> isFrpsRunning() async {
    try {
      return await _channel.invokeMethod('isFrpsRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isFrpcRunning() async {
    try {
      return await _channel.invokeMethod('isFrpcRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkPort(int port) async {
    try {
      return await _channel.invokeMethod('checkPort', {'port': port}) ?? false;
    } catch (_) {
      return false;
    }
  }
}