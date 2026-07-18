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