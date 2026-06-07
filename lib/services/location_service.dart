import 'dart:async';
import 'dart:math';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orbitx/dto/location_dto.dart';

class LocationService {
  double speed = 0.0;
  int periodicUpdateIntervalSeconds = 1;
  late StreamController<AccelerationData> locationStreamController;
  LocationService() {
    locationStreamController = StreamController<AccelerationData>.broadcast();
  }

  AccelerationData acceleration = AccelerationData(
    point: GeoPoint(latitude: 0.0, longitude: 0.0),
    acceleration: 0.0,
    speed: 0.0,
    timestamp: DateTime.now(),
    altitude: 411.0,
  );

  Future<String> getCurrentLocation() async {
    // Simulate fetching location data
    await Future.delayed(Duration(seconds: 2));
    return "Latitude: 37.7749, Longitude: -122.4194"; // Example coordinates
  }

  void startLocationUpdates() {
    if (speed != 0.0) {
      // Simulate location updates
      Timer.periodic(Duration(seconds: periodicUpdateIntervalSeconds), (timer) {
        // Update location data here and add to stream
        final acc = randomPointAt3DDistance(
          acceleration.point.latitude,
          acceleration.point.longitude,
          acceleration.altitude,
          speed *
              periodicUpdateIntervalSeconds /
              3600.0, // distance = speed * time
          acceleration.speed,
        );
        locationStreamController.add(acc);
        acceleration = acc; // Example coordinates
        if (speed == 0.0) {
          timer.cancel();
          startLocationUpdates(); // Restart with real location updates
        }
      });
    } else {
      StreamSubscription<Position>? subscription;
      subscription =
          Geolocator.getPositionStream(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen((Position position) {
            final timestamp = DateTime.now();
            // Update location data here and add to stream
            final acc = AccelerationData(
              point: GeoPoint(
                latitude: position.latitude,
                longitude: position.longitude,
              ),
              acceleration:
                  (position.speed - acceleration.speed) /
                  timestamp
                      .difference(acceleration.timestamp)
                      .inSeconds, // acc = dx / dt
              speed: position.speed,
              timestamp: timestamp,
              altitude: position.altitude,
            );
            locationStreamController.add(acc);
            acceleration = acc;
            if (speed != 0.0) {
              subscription?.cancel();
              startLocationUpdates(); // Restart with fake location updates
            }
          });
    }
  }

  set fakespeed(double value) {
    speed = value; // Reset speed
  }

  set fakePeriodicUpdateIntervalSeconds(int updateIntervalSeconds) {
    periodicUpdateIntervalSeconds = updateIntervalSeconds;
  }

  // AccelerationData calculate3DDistanceKm(AccelerationData p2) {
  //   const double earthRadiusKm = 6371.0;

  //   // Convert degrees to radians
  //   double lat1Rad = acceleration.point.latitude * pi / 180.0;
  //   double lat2Rad = p2.point.latitude * pi / 180.0;
  //   double lon1Rad = acceleration.point.longitude * pi / 180.0;
  //   double lon2Rad = p2.point.longitude * pi / 180.0;

  //   // Differences
  //   double deltaLat = lat2Rad - lat1Rad;
  //   double deltaLon = lon2Rad - lon1Rad;

  //   // Haversine formula for ground distance
  //   double a =
  //       sin(deltaLat / 2) * sin(deltaLat / 2) +
  //       cos(lat1Rad) * cos(lat2Rad) * sin(deltaLon / 2) * sin(deltaLon / 2);
  //   double haversineDistanceKm = 2 * earthRadiusKm * asin(sqrt(a));

  //   // Altitude difference converted from meters to kilometers
  //   double deltaAltitudeKm = (p2.altitude - p1.altitude) / 1000.0;

  //   // 3D Pythagorean theorem
  //   double distance3DKm = sqrt(
  //     pow(haversineDistanceKm, 2) + pow(deltaAltitudeKm, 2),
  //   );

  //   return AccelerationData(
  //     point: GeoPoint(latitude: 0.0, longitude: 0.0),
  //     acceleration: distance3DKm,
  //     timestamp: DateTime.now(),
  //     altitude: 0.0,
  //   );
  // }

  AccelerationData randomPointAt3DDistance(
    double latitude,
    double longitude,
    double altitude,
    double distanceKm,
    double speedLast,
  ) {
    const earthRadiusKm = 6371.0;

    final random = Random();

    // Random altitude change (±20% of total distance)
    final deltaAltitudeKm = (random.nextDouble() * 0.4 - 0.2) * distanceKm;

    // Remaining ground distance
    final groundDistanceKm = sqrt(
      distanceKm * distanceKm - deltaAltitudeKm * deltaAltitudeKm,
    );

    // Random direction
    final bearing = random.nextDouble() * 2 * pi;

    final lat1 = latitude * pi / 180.0;
    final lon1 = longitude * pi / 180.0;

    final angularDistance = groundDistanceKm / earthRadiusKm;

    final lat2 = asin(
      sin(lat1) * cos(angularDistance) +
          cos(lat1) * sin(angularDistance) * cos(bearing),
    );

    final lon2 =
        lon1 +
        atan2(
          sin(bearing) * sin(angularDistance) * cos(lat1),
          cos(angularDistance) - sin(lat1) * sin(lat2),
        );

    return AccelerationData(
      point: GeoPoint(
        latitude: lat2 * 180.0 / pi,
        longitude: lon2 * 180.0 / pi,
      ),
      acceleration: (speed - speedLast) / periodicUpdateIntervalSeconds,
      timestamp: DateTime.now(),
      altitude: altitude + deltaAltitudeKm * 1000.0,
      speed: speed,
    );
  }
}
