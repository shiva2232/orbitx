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
  bool simulate = false;
  bool _dialogShowing = false;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccelerationData>(
      stream: locationService.locationStreamController.stream,
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.data!.acceleration.abs() >= 29.4 &&  // 3 * 9.81(gravity)
            !_dialogShowing) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            _dialogShowing = true;

            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Possible Accident'),
                content: Text(
                  'Detected acceleration: '
                  '${snapshot.data!.acceleration.toStringAsFixed(2)} m/s²',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('I am OK'),
                  ),
                ],
              ),
            );

            _dialogShowing = false;
          });
        }
        ;
        return Stack(
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(
                  snapshot.hasData
                      ? pi *
                            snapshot.data!.acceleration /
                            (2 * (snapshot.data!.acceleration + 200))
                      : 0, // 0m/s^2 - 0 degree, 200m/s^2 - 45 degree, infinite m/s^2 - 90 degree
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
            ),

            if (snapshot.hasData)
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Speed: ${snapshot.data!.speed.toStringAsFixed(2)} m/s",
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        "Acceleration: ${snapshot.data!.acceleration.toStringAsFixed(2)} m/s²",
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        "Altitude: ${snapshot.data!.altitude.toStringAsFixed(2)} m",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 20,
              left: 20,
              width: MediaQuery.of(context).size.width - 40,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shadowColor: Colors.redAccent,
                    elevation: 10,
                  ),
                  onPressed: () {
                    locationService.fakespeed = locationService.speed == 100
                        ? 0
                        : 100;
                    // Random().nextDouble() * 100; // Simulate speed changes
                    debugPrint("Fake speed updated: ${locationService.speed}");
                  },
                  child: const Text("End Auto Navigation"),
                ),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              height: MediaQuery.of(context).size.height - 120,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    activeColor: Colors.black,
                    inactiveColor: Colors.white,
                    overlayColor: WidgetStateProperty.all(Colors.blue),
                    thumbColor: Colors.yellow,
                    secondaryActiveColor: Colors.red,
                    value: snapshot.hasData
                        ? snapshot.data!.zoomOveride != -1
                              ? snapshot.data!.zoomOveride
                              : snapshot.data!.speed.clamp(0, 17).toDouble()
                        : 5.0,
                    min: 0,
                    max: 17,
                    divisions: 170,
                    label: "Zoom",
                    onChanged: (value) {
                      locationService.fakeZoom = value;
                    },
                    onChangeStart: (value) {
                      locationService.fakeZoom = value; // Simulate zoom changes
                    },
                    onChangeEnd: (value) {
                      locationService.fakeZoom = -1; // Reset zoom override
                    },
                  ),
                ),
              ),
            ),
          ],
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
          if (simulate) {
            locationService.fakespeed = Random().nextDouble() * 100;
          }
          locationService.startLocationUpdates();
          locationService.locationStreamController.stream.listen((
            accelerationData,
          ) {
            debugPrint(
              "Received location update: ${accelerationData.point.latitude}, ${accelerationData.point.longitude}, Speed: ${accelerationData.speed}, Acceleration: ${accelerationData.acceleration}",
            );
            controller.setZoom(
              zoomLevel: accelerationData.zoomOveride != -1
                  ? 17 - accelerationData.zoomOveride
                  : 2 + locationService.zoomForSpeed(accelerationData.speed),
            ); //  + (10 - accelerationData.speed / 10)  0-17 log zooming
            controller.moveTo(
              GeoPoint(
                latitude: accelerationData.point.latitude,
                longitude: accelerationData.point.longitude,
              ),
              animate: true,
            );
          });
          if (simulate) {
            Timer.periodic(Duration(seconds: 5), (timer) {
              locationService.fakespeed =
                  Random().nextDouble() * 1; // Simulate speed changes
              debugPrint("Fake speed updated: ${locationService.speed}");
            });
          }
        })
        .catchError((error) {
          debugPrint("Error initializing location service: $error");
        });
  }
}
