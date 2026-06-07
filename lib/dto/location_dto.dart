
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';

class AccelerationData {
  final GeoPoint point;
  final double acceleration;
  final double speed;
  final DateTime timestamp;
  final double altitude;
  final double zoomOveride;

  AccelerationData({
    required this.point,
    required this.acceleration,
    required this.speed,
    required this.timestamp,
    required this.altitude,
    required this.zoomOveride,
  });

  factory AccelerationData.fromMap(Map<String, dynamic> map) {
    return AccelerationData(
      point: map['point'] as GeoPoint,
      acceleration: (map['acceleration'] as num).toDouble(),
      speed: (map['speed'] as num).toDouble(),
      timestamp: map['timestamp'] as DateTime,
      altitude: (map['altitude'] as num).toDouble(),
      zoomOveride: (map['zoomOveride'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'point': point,
      'acceleration': acceleration,
      'speed': speed,
      'timestamp': timestamp,
      'altitude': altitude,
      'zoomOveride': zoomOveride,
    };
  }
}
