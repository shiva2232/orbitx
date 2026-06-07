import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:orbitx/dto/location_dto.dart';
import 'package:orbitx/services/location_service.dart';
import 'package:permission_handler/permission_handler.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late LocationService locationService;
  final MapController controller = MapController(
    initMapWithUserPosition: UserTrackingOption(
      enableTracking: true,
      unFollowUser: false,
    ),
  );
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccelerationData>(
      stream: locationService.locationStreamController.stream,
      builder: (context, snapshot) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(
              snapshot.hasData
                  ? pi *
                        snapshot.data!.acceleration /
                        (2 * (snapshot.data!.acceleration + 200))
                  : 0, // 0ms - 0 degree, 200ms - 45 degree, infinite ms - 90 degree
            ),
          child: OSMFlutter(
            controller: controller,
            osmOption: OSMOption(
              enableRotationByGesture: true,
              roadConfiguration: RoadOption(
                roadColor: Colors.grey,
                roadWidth: 10,
              ),
              userTrackingOption: UserTrackingOption(
                enableTracking: true,
                unFollowUser: false,
              ),
              zoomOption: ZoomOption(
                minZoomLevel: 2,
                maxZoomLevel: 19,
                initZoom: 10,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    Permission.location.isDenied.then((value) {
      if (value) {
        Permission.location.request().then((status) {
          if (status.isGranted) {
            listenToLocationUpdates();
          }
        });
      }
    });
    Permission.location.isGranted.then((value) {
      if (value) {
        listenToLocationUpdates();
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    locationService.locationStreamController.close();
    super.dispose();
  }

  void listenToLocationUpdates() async {
    locationService
        .init()
        .then((_) {
          debugPrint("Location service initialized");

          locationService.fakespeed = Random().nextDouble() * 100;
          locationService.startLocationUpdates();
          locationService.locationStreamController.stream.listen((
            accelerationData,
          ) {
            debugPrint(
              "Received location update: ${accelerationData.point.latitude}, ${accelerationData.point.longitude}, Speed: ${accelerationData.speed}, Acceleration: ${accelerationData.acceleration}",
            );
            controller.setZoom(
              zoomLevel:
                  2 + locationService.zoomForSpeed(accelerationData.speed),
            ); //  + (10 - accelerationData.speed / 10)  0-17 log zooming
            controller.moveTo(
              GeoPoint(
                latitude: accelerationData.point.latitude,
                longitude: accelerationData.point.longitude,
              ),
              animate: true,
            );
          });
          Timer.periodic(Duration(seconds: 5), (timer) {
            locationService.fakespeed =
                Random().nextDouble() * 100; // Simulate speed changes
            debugPrint("Fake speed updated: ${locationService.speed}");
          });
        })
        .catchError((error) {
          debugPrint("Error initializing location service: $error");
        });
  }
}
