import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  static Future<String> getDeviceName() async {
    if (Platform.isAndroid) {
      final info = await _plugin.androidInfo;

      // Example: "Google Pixel 8"
      return "${info.manufacturer} ${info.model}";
    }

    if (Platform.isIOS) {
      final info = await _plugin.iosInfo;

      // Example: "iPhone15,2"
      return info.utsname.machine;
    }

    if (Platform.isWindows) {
      final info = await _plugin.windowsInfo;
      return info.computerName;
    }

    if (Platform.isLinux) {
      final info = await _plugin.linuxInfo;
      return info.prettyName;
    }

    if (Platform.isMacOS) {
      final info = await _plugin.macOsInfo;
      return info.computerName;
    }

    return "Unknown Device";
  }
}