import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:wireguard_flutter_plus/wireguard_flutter_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:orbitx/utils/db.dart';
import 'package:orbitx/utils/device_info.dart';
import 'package:orbitx/utils/wg.dart';
import 'package:shared_preferences/shared_preferences.dart';

// final config = '''
// [Interface]
// PrivateKey = $privateKey
// Address = 10.0.0.2/32
// DNS = 1.1.1.1
//
// [Peer]
// PublicKey = $serverPublicKey
// Endpoint = vpn.example.com:51820
// AllowedIPs = 0.0.0.0/0
// PersistentKeepalive = 25
// ''';
//
// await wireguard.startVpn(
//   serverAddress: 'vpn.example.com:51820',
//   wgQuickConfig: config,
// );

class WireGuardPeer {
  final String endpointIp;
  final int endpointPort;
  final String peerPublicKey;
  final String myPrivateKey;
  final String myAddress;

  WireGuardPeer({
    required this.endpointIp,
    required this.endpointPort,
    required this.peerPublicKey,
    required this.myPrivateKey,
    required this.myAddress,
  });
}

class WireGuardConfigGenerator {

  static String generate({
    required WireGuardPeer peer,

    String? dns,

    String allowedIps = "0.0.0.0/0",

    int persistentKeepalive = 15,
  }) {

    final buffer = StringBuffer();

    buffer.writeln("[Interface]");
    buffer.writeln("PrivateKey = ${peer.myPrivateKey}");
    buffer.writeln("Address = ${peer.myAddress}");

    if (dns != null) {
      buffer.writeln("DNS = $dns");
    }

    buffer.writeln();

    buffer.writeln("[Peer]");
    buffer.writeln("PublicKey = ${peer.peerPublicKey}");
    buffer.writeln("Endpoint = ${peer.endpointIp}:${peer.endpointPort}");
    buffer.writeln("AllowedIPs = $allowedIps");
    buffer.writeln("PersistentKeepalive = $persistentKeepalive");

    return buffer.toString();
  }
}

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

class StunConstants {
  static const int bindingRequest = 0x0001;
  static const int bindingResponse = 0x0101;

  static const int magicCookie = 0x2112A442;

  static const int mappedAddress = 0x0001;
  static const int xorMappedAddress = 0x0020;

  static const int ipv4 = 0x01;
}

class StunAttribute {
  final int type;
  final Uint8List value;

  StunAttribute(this.type, this.value);
}

class StunMessage {
  final Uint8List transactionId;

  StunMessage(this.transactionId);

  factory StunMessage.request() {
    final random = Random.secure();

    final id = Uint8List(12);

    for (int i = 0; i < 12; i++) {
      id[i] = random.nextInt(256);
    }

    return StunMessage(id);
  }

  Uint8List encode() {
    final buffer = BytesBuilder();

    final data = ByteData(20);

    data.setUint16(0, StunConstants.bindingRequest);
    data.setUint16(2, 0);
    data.setUint32(4, StunConstants.magicCookie);

    for (int i = 0; i < 12; i++) {
      data.setUint8(8 + i, transactionId[i]);
    }

    buffer.add(data.buffer.asUint8List());

    return buffer.toBytes();
  }
}

class StunResult {
  final InternetAddress address;
  final int port;

  StunResult(this.address, this.port);
}

class StunClient {
  RawDatagramSocket? _socket;

  InternetAddress? publicAddress;
  int? publicPort;

  Timer? _keepAliveTimer;

  late void Function(InternetAddress address, int port, bool changed)
  onEndpointChanged;

  Future<void> _sendBindingRequest(String host, int port) async {
    final request = StunMessage.request();

    _socket!.send(request.encode(), InternetAddress(host), port);
  }

  StunResult? _parse(Uint8List bytes) {
    if (bytes.length < 20) {
      return null;
    }

    final data = ByteData.sublistView(bytes);

    int offset = 20;

    while (offset + 4 <= bytes.length) {
      final type = data.getUint16(offset);
      final length = data.getUint16(offset + 2);

      if (offset + 4 + length > bytes.length) {
        return null;
      }

      if (type == StunConstants.xorMappedAddress) {
        final family = bytes[offset + 5];

        if (family != 0x01) {
          return null; // IPv4 only
        }

        final xPort = data.getUint16(offset + 6);
        final port = xPort ^ 0x2112;

        final cookie = [0x21, 0x12, 0xA4, 0x42];

        final ip = List<int>.generate(4, (i) {
          return bytes[offset + 8 + i] ^ cookie[i];
        });

        return StunResult(
          InternetAddress.fromRawAddress(Uint8List.fromList(ip)),
          port,
        );
      }

      offset += 4 + length;

      // 32-bit padding
      while (offset % 4 != 0) {
        offset++;
      }
    }

    return null;
  }

  void _onSocketData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final packet = _socket!.receive();

    if (packet == null) return;

    final result = _parse(packet.data);

    if (result == null) return;

    final changed =
        publicAddress?.address != result.address.address ||
        publicPort != result.port;

    publicAddress = result.address;
    publicPort = result.port;

    onEndpointChanged.call(result.address, result.port, changed);
  }

  void listen(void Function(InternetAddress, int, bool) callback) {
    onEndpointChanged = callback;
  }

  Future<void> start({
    required String stunHost,
    required int stunPort,
    required void Function(InternetAddress address, int port, bool changed)
    onEndpointChanged,
  }) async {
    this.onEndpointChanged = onEndpointChanged;

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onSocketData);

    await _sendBindingRequest(stunHost, stunPort);

    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendBindingRequest(stunHost, stunPort),
    );
  }

  Future<void> stop() async {
    _keepAliveTimer?.cancel();
    _socket?.close();
  }

  RawDatagramSocket getSocket() {
    return _socket!;
  }
}

class KeyUtils {
  late String _privateKey;
  late String _publicKey;
  final StunClient stun = StunClient();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  late String _uuid;
  String _deviceName = '';
  bool isHost = false;
  late SignalingPeer peer;
  late SignalingPeer current;
  final vpn = WireGuardFlutter.instance;

  KeyUtils(this.isHost) {
    DeviceService.getDeviceName().then((dn) {
      _deviceName = dn;
    });
    
    saveOrGetKey();
  }

Future<bool> init()async {
  vpn.checkVpnPermission().then((granted) async {
    if (granted) {
      await vpn.initialize(
        interfaceName: 'wg0',
        vpnName: "Orban VPN", // Visible Name in Settings/Notifications
      );
      await saveOrGetKey();
    } else {
      init();
    }
  });
  return true;
}

  Future<Map<String, String>> _generateKey() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final privateKey = base64Encode(await keyPair.extractPrivateKeyBytes());
    final publicKey = base64Encode((await keyPair.extractPublicKey()).bytes);
    return {"privateKey": privateKey, "publicKey": publicKey};
  }

  Future<void> saveOrGetKey() async {
    final prefs = await SharedPreferences.getInstance();
    String? key = prefs.getString('private_key');
    if (key == null) {
      final keys = await _generateKey();
      _privateKey = keys["privateKey"]!;
      _publicKey = keys["publicKey"]!;
      prefs.setString('private_key', _privateKey);
      prefs.setString('public_key', _publicKey);
    } else {
      _privateKey = key;
      _publicKey = prefs.getString('public_key')!;
    }
  }

  Future<void> startVPN(String name) async {
    await stun.start(
      stunHost: "stun.l.google.com",
      stunPort: 19302,
      onEndpointChanged: (InternetAddress address, int port, bool changed) {
        print("Public IP : ${address.address}");
        print("Public Port : $port");
        print("Changed : $changed");
        if (changed) {
          current=SignalingPeer(
                  uid: name,
                  publicIp: address.address,
                  publicPort: port,
                  wireguardPublicKey: _publicKey,
                  deviceName: _deviceName,
                  online: true,
                  networkType: "Testing",
                );
          _database
              .ref("peers/$_uuid/${isHost ? 'host' : 'peer'}")
              .update(
                current.toJson(),
              );
              rerun();
        }
      },
    );
  }

  Future<void> rerun()async {
          vpn.stopVpn();
          final config = generateConfig(
            WireGuardPeer(
              endpointIp: peer.publicIp,
              endpointPort: peer.publicPort,
              peerPublicKey: _publicKey,
              myPrivateKey: _privateKey,
              myAddress: '${current.publicIp}:${current.publicPort}'),
            );
          vpn.startVpn(
            serverAddress: "${peer.publicIp}:${peer.publicPort}",
            wgQuickConfig: config,
            providerBundleIdentifier: "com.home.vpn",
          );
  }

  String generateConfig(WireGuardPeer peer) {
    return WireGuardConfigGenerator.generate(peer: peer);
  }

  Future<bool> pair(String uuid) async {
    _uuid = uuid;
    _database.ref("peers/$_uuid/${isHost ? 'peer' : 'host'}").onValue.listen((
      event,
    ) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        final peer = SignalingPeer(
          uid: data['uid'],
          publicIp: data['publicIp'],
          publicPort: data['publicPort'],
          wireguardPublicKey: data['wireguardPublicKey'],
          deviceName: data['deviceName'],
          online: data['online'],
          networkType: data['networkType'],
        );
        this.peer = peer;
        rerun();
      }
    });
    return true;
  }

  Future<void> destroy() async {
    vpn.stopVpn();
    await stun.stop();
  }
}
