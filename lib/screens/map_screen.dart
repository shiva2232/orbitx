import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_osm_plugin/flutter_osm_plugin.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:orbitx/helper/location_group.dart' as lg;
import 'package:orbitx/services/location_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

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
  

  late lg.EventTrackingService eventTrackingService;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _eventIdController = TextEditingController();
  bool _isHostMode = true;
  bool _isJoined = false;
  String? _hostEventId;
  final Map<String, GeoPoint> _remoteMarkers = {};
  List<lg.UserLocation> _connectedUsers = [];
  StreamSubscription<List>? _connectedUsersSubscription;

  void _showHostJoinBottomSheet() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Live Tracking',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Host a session or join a friend. Scan a code or share the event ID to connect everyone in real time.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    ToggleButtons(
                      isSelected: [_isHostMode, !_isHostMode],
                      onPressed: (index) {
                        setState(() {
                          _isHostMode = index == 0;
                          if (_isHostMode && _hostEventId != null) {
                            _eventIdController.text = _hostEventId!;
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      selectedColor: Colors.white,
                      fillColor: Colors.redAccent,
                      color: Colors.black87,
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text('Host'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text('Join'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_isHostMode) ...[
                      const Text(
                        'Host session',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              if (_hostEventId != null) ...[
                                Container(
                                  width: 180,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _hostEventId!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  _hostEventId!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ] else ...[
                                const Text(
                                  'Create a shareable event code for your group.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else ...[
                      const Text(
                        'Join session',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan event QR code'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                          onPressed: () async {
                          final scanned = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                              builder: (_) => const _QRCodeScannerPage(),
                            ),
                          );
                          if (scanned != null && scanned.isNotEmpty) {
                            setState(() {
                              _eventIdController.text = scanned;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    TextField(
                      controller: _eventIdController,
                      readOnly: _isHostMode,
                      decoration: InputDecoration(
                        labelText: 'Event ID',
                        border: const OutlineInputBorder(),
                        suffixIcon: _isHostMode
                            ? IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: () {
                                  setState(() {
                                    _hostEventId = const Uuid().v4().replaceAll('-', '');
                                    _eventIdController.text = _hostEventId!;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        if (!_isHostMode) {
                          _hostEventId = value.trim();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () {
                        if (_isHostMode) {
                          _startHosting();
                        } else {
                          _joinEvent();
                        }
                        Navigator.of(context).pop();
                      },
                      child: Text(_isHostMode ? 'Start hosting' : 'Join event'),
                    ),
                    const SizedBox(height: 16),
                    if (_isHostMode)
                      Text(
                        'Share the generated QR code or copied event ID with your joiners. Your location will update in real time for everyone in the session.',
                        style: TextStyle(color: Colors.grey[700]),
                      )
                    else
                      Text(
                        'Enter the host event ID or scan the QR code to join. Once connected, all active devices will appear on the map.',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startHosting() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackbar('Please enter your name.');
      return;
    }

    _hostEventId ??= const Uuid().v4().replaceAll('-', '');
    _eventIdController.text = _hostEventId!;
    await _joinEventInternal(eventId: _hostEventId!, userName: name);
  }

  Future<void> _joinEvent() async {
    final eventId = _eventIdController.text.trim();
    final name = _nameController.text.trim();

    if (eventId.isEmpty) {
      _showSnackbar('Please enter or scan an event ID.');
      return;
    }
    if (name.isEmpty) {
      _showSnackbar('Please enter your name.');
      return;
    }

    _hostEventId = eventId;
    await _joinEventInternal(eventId: eventId, userName: name);
  }

  Future<void> _joinEventInternal({required String eventId, required String userName}) async {
    try {
      await eventTrackingService.joinEvent(eventId: eventId, userName: userName);
      setState(() {
        _isJoined = true;
        _isHostMode = _hostEventId == eventId;
        _eventIdController.text = eventId;
      });
      _subscribeConnectedUsers();
      _showSnackbar('Connected to event $eventId');
    } catch (e) {
      _showSnackbar('Failed to connect: $e');
    }
  }

  void _subscribeConnectedUsers() {
    _connectedUsersSubscription?.cancel();
    _connectedUsersSubscription = eventTrackingService.usersStream.listen((users) {
      if (!mounted) return;
      final casted = (users).cast<lg.UserLocation>();
      setState(() {
        _connectedUsers = casted;
      });
      _refreshRemoteMarkers(casted);
    });
  }

  Future<void> _refreshRemoteMarkers(List<lg.UserLocation> users) async {
    for (final entry in _remoteMarkers.entries) {
      try {
        await controller.removeMarker(entry.value);
      } catch (_) {}
    }
    _remoteMarkers.clear();

    for (final user in users) {
      final remotePoint = GeoPoint(latitude: user.latitude, longitude: user.longitude);
      try {
        await controller.addMarker(
          remotePoint,
          markerIcon: MarkerIcon(
            icon: Icon(
              Icons.location_pin,
              color: Colors.blueAccent,
              size: 48,
            ),
          ),
        );
        _remoteMarkers[user.name] = remotePoint;
      } catch (_) {
        // fail gracefully if duplicate or invalid marker update
      }
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    eventTrackingService = lg.EventTrackingService();
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
    _connectedUsersSubscription?.cancel();
    eventTrackingService.dispose();
    controller.dispose();
    locationService.locationStreamController.close();
    super.dispose();
  }

  void listenToLocationUpdates() async {
    try {
      await locationService.init();
      debugPrint("Location service initialized");
      if (simulate) {
        locationService.fakespeed = Random().nextDouble() * 100;
      }
      locationService.startLocationUpdates();
      locationService.locationStreamController.stream.listen(
        (accelerationData) async {
          debugPrint(
            "Received location update: ${accelerationData.point.latitude}, ${accelerationData.point.longitude}, Speed: ${accelerationData.speed}, Acceleration: ${accelerationData.acceleration}",
          );
          controller.setZoom(
            zoomLevel: accelerationData.zoomOveride != -1
                ? 17 - accelerationData.zoomOveride
                : 2 + locationService.zoomForSpeed(accelerationData.speed),
          );
          await controller.moveTo(
            GeoPoint(
              latitude: accelerationData.point.latitude,
              longitude: accelerationData.point.longitude,
            ),
            animate: true,
          );

          if (_isJoined) {
            try {
              await eventTrackingService.updateLocation(
                latitude: accelerationData.point.latitude,
                longitude: accelerationData.point.longitude,
                altitude: accelerationData.altitude,
                speed: accelerationData.speed,
                acceleration: accelerationData.acceleration,
              );
            } catch (_) {
              // Ignore publish failures so live tracking continues.
            }
          }
        },
      );
      if (simulate) {
        Timer.periodic(Duration(seconds: 5), (timer) {
          locationService.fakespeed = Random().nextDouble() * 1;
          debugPrint("Fake speed updated: ${locationService.speed}");
        });
      }
    } catch (error) {
      debugPrint("Error initializing location service: $error");
    }
  }

  void _focusOnUser(lg.UserLocation user) {
    try {
      final point = GeoPoint(latitude: user.latitude, longitude: user.longitude);
      controller.setZoom(zoomLevel: 16);
      controller.moveTo(point, animate: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          OSMFlutter(
            controller: controller,
            osmOption: OSMOption(
              userTrackingOption: UserTrackingOption(enableTracking: true, unFollowUser: false),
              zoomOption: ZoomOption(initZoom: 12, minZoomLevel: 2, maxZoomLevel: 18, stepZoom: 1.0),
              showDefaultInfoWindow: false,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _showHostJoinBottomSheet(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: const [Icon(Icons.qr_code), SizedBox(width: 8), Text('Generate QR code')],
                      ),
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () async {
                      setState(() => simulate = !simulate);
                      _showSnackbar(simulate ? 'Simulation ON' : 'Simulation OFF');
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [Icon(simulate ? Icons.speed : Icons.gps_fixed), const SizedBox(width: 8), Text(simulate ? 'Simulate' : 'Live')],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Connected users strip
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: StreamBuilder<List<dynamic>>(
              stream: eventTrackingService.usersStream,
              builder: (context, snapshot) {
                final users = snapshot.data ?? _connectedUsers;
                if (users.isEmpty) return const SizedBox.shrink();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: users.map<Widget>((u) {
                      final user = u as lg.UserLocation;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          avatar: const Icon(Icons.person, size: 18),
                          label: Text(user.name),
                          onPressed: () => _focusOnUser(user),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QRCodeScannerPage extends StatefulWidget {
  const _QRCodeScannerPage({Key? key}) : super(key: key);

  @override
  State<_QRCodeScannerPage> createState() => _QRCodeScannerPageState();
}

class _QRCodeScannerPageState extends State<_QRCodeScannerPage> {
  final ms.MobileScannerController _scannerController = ms.MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: Icon(_scannerController.torchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ],
      ),
      body: ms.MobileScanner(
        controller: _scannerController,
        onDetect: (capture) {
          if (_isProcessing) return;
          final barcode = capture.barcodes.firstWhere(
            (barcode) => barcode.rawValue != null,
            orElse: () => ms.Barcode(rawValue: null),
          );
          final rawValue = barcode.rawValue;
          if (rawValue == null) return;

          _isProcessing = true;
          Navigator.of(context).pop(rawValue);
        },
      ),
    );
  }
}
