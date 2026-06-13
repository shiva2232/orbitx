import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

class UserLocation {
  final String name;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double acceleration;
  final int timestamp;

  UserLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.acceleration,
    required this.timestamp,
  });

  factory UserLocation.fromMap(String name, Map<dynamic, dynamic> json) {
    return UserLocation(
      name: name,
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      altitude: (json['altitude'] ?? 0).toDouble(),
      speed: (json['speed'] ?? 0).toDouble(),
      acceleration: (json['acceleration'] ?? 0).toDouble(),
      timestamp: (json['timestamp'] ?? 0) as int,
    );
  }
}

class EventTrackingService {
  static const timeoutMs = 15000;

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  String? _eventId;
  String? _userName;

  DatabaseReference? _userRef;

  StreamSubscription? _subscription;

  Timer? _heartbeatTimer;

  final StreamController<List> _usersController = StreamController.broadcast();

  Stream<List> get usersStream => _usersController.stream;

  Future joinEvent({required String eventId, required String userName}) async {
    _eventId = eventId;
    _userName = userName;

    _userRef = _db.ref('events/$_eventId/users/$userName');

    _subscription?.cancel();

    _subscription = _db
        .ref('events/$_eventId/users')
        .onValue
        .listen(_handleUsersUpdate);

    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _userRef?.update({'timestamp': ServerValue.timestamp});
    });

    await _userRef!.onDisconnect().remove();
  }

  Future updateLocation({
    required double latitude,
    required double longitude,
    required double altitude,
    required double speed,
    required double acceleration,
  }) async {
    if (_userRef == null) return;

    await _userRef!.set({
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'acceleration': acceleration,
      'timestamp': ServerValue.timestamp,
    });
  }

  void _handleUsersUpdate(DatabaseEvent event) {
    final value = event.snapshot.value;

    if (value == null || value is! Map<dynamic, dynamic>) {
      _usersController.add([]);
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final users = <UserLocation>[];

    value.forEach((key, rawUser) {
      if (key == _userName) {
        return;
      }

      if (rawUser is! Map<dynamic, dynamic>) {
        return;
      }

      final user = UserLocation.fromMap(key.toString(), rawUser);

      if (now - user.timestamp > timeoutMs) {
        return;
      }

      users.add(user);
    });

    _usersController.add(users);
  }

  Future leave() async {
    _heartbeatTimer?.cancel();

    await _userRef?.remove();

    await _subscription?.cancel();

    _eventId = null;
    _userName = null;
    _userRef = null;
  }

  Future dispose() async {
    await leave();
    await _usersController.close();
  }
}
