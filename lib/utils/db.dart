import 'package:firebase_database/firebase_database.dart';

class SignalingPeer {
  final String uid;
  final String publicIp;
  final int publicPort;
  final String wireguardPublicKey;
  final String deviceName;
  final bool online;
  final String networkType;

  SignalingPeer({
    required this.uid,
    required this.publicIp,
    required this.publicPort,
    required this.wireguardPublicKey,
    required this.deviceName,
    required this.online,
    required this.networkType,
  });

  Map<String, dynamic> toJson() {
    return {
      "uid": uid,
      "publicIp": publicIp,
      "publicPort": publicPort,
      "wireguardPublicKey": wireguardPublicKey,
      "deviceName": deviceName,
      "online": online,
      "networkType": networkType,
      "updatedAt": DateTime.now().millisecondsSinceEpoch,
      "lastSeen": DateTime.now().millisecondsSinceEpoch,
      "protocolVersion": 1,
    };
  }
}
