import 'package:flutter/material.dart';

class WeatherUtils {
  static IconData weatherCodeIcon(String? code) {
    switch (code) {
      case "113":
        return Icons.wb_sunny;

      case "116":
      case "119":
      case "122":
        return Icons.cloud;

      case "143":
      case "248":
      case "260":
        return Icons.foggy;

      case "176":
      case "263":
      case "266":
      case "281":
      case "293":
      case "296":
        return Icons.water_drop;

      case "299":
      case "302":
      case "305":
      case "308":
      case "311":
      case "314":
        return Icons.grain;

      case "200":
      case "386":
      case "389":
      case "392":
      case "395":
        return Icons.thunderstorm;

      case "227":
      case "230":
      case "320":
      case "323":
      case "326":
      case "329":
      case "332":
      case "335":
      case "338":
        return Icons.ac_unit;

      default:
        return Icons.cloud;
    }
  }

  static String formatTime(String value) {
    final raw = int.tryParse(value) ?? 0;

    final hour = raw ~/ 100;

    return "${hour.toString().padLeft(2, '0')}:00";
  }
}