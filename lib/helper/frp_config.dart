enum ProxyType { tcp, udp, http, https, stcp, xtcp }

/// Helper extension to serialize enums safely to TOML string values
extension ProxyTypeExtension on ProxyType {
  String get value => toString().split('.').last;
}

// ============================================================================
// FRP CLIENT CONFIGURATION (frpc)
// ============================================================================

class FrpProxyConfig {
  final String name;
  final ProxyType type;
  final String localIp;
  final int localPort;
  final int? remotePort; // Required for TCP/UDP
  final List<String>? customDomains; // Required for HTTP/HTTPS
  final String? subdomain;

  const FrpProxyConfig({
    required this.name,
    required this.type,
    required this.localIp,
    required this.localPort,
    this.remotePort,
    this.customDomains,
    this.subdomain,
  });

  /// Serializes individual proxy section into TOML string format
  String toTomlString() {
    final buffer = StringBuffer();
    buffer.writeln('[[proxies]]');
    buffer.writeln('name = "$name"');
    buffer.writeln('type = "${type.value}"');
    buffer.writeln('localIP = "$localIp"');
    buffer.writeln('localPort = $localPort');

    if (remotePort != null) {
      buffer.writeln('remotePort = $remotePort');
    }

    if (customDomains != null && customDomains!.isNotEmpty) {
      final domains = customDomains!.map((d) => '"$d"').join(', ');
      buffer.writeln('customDomains = [$domains]');
    }

    if (subdomain != null && subdomain!.isNotEmpty) {
      buffer.writeln('subdomain = "$subdomain"');
    }

    return buffer.toString();
  }
}

class FrpcConfig {
  final String serverAddr;
  final int serverPort;
  final String? authToken;
  final List<FrpProxyConfig> proxies;

  const FrpcConfig({
    required this.serverAddr,
    this.serverPort = 7000,
    this.authToken,
    this.proxies = const [],
  });

  /// Generates full frpc.toml configuration string
  String toTomlString() {
    final buffer = StringBuffer();

    buffer.writeln('# Generated frpc.toml');
    buffer.writeln('serverAddr = "$serverAddr"');
    buffer.writeln('serverPort = $serverPort');

    if (authToken != null && authToken!.isNotEmpty) {
      buffer.writeln('\n[auth]');
      buffer.writeln('token = "$authToken"');
    }

    if (proxies.isNotEmpty) {
      buffer.writeln();
      for (final proxy in proxies) {
        buffer.writeln(proxy.toTomlString());
      }
    }

    return buffer.toString();
  }
}

// ============================================================================
// FRP SERVER CONFIGURATION (frps)
// ============================================================================

class FrpsWebServerConfig {
  final String addr;
  final int port;
  final String user;
  final String password;

  const FrpsWebServerConfig({
    this.addr = "0.0.0.0",
    this.port = 7500,
    required this.user,
    required this.password,
  });

  String toTomlString() {
    final buffer = StringBuffer();
    buffer.writeln('[webServer]');
    buffer.writeln('addr = "$addr"');
    buffer.writeln('port = $port');
    buffer.writeln('user = "$user"');
    buffer.writeln('password = "$password"');
    return buffer.toString();
  }
}

class FrpsConfig {
  final int bindPort;
  final String bindAddr;
  final int? vhostHttpPort;
  final int? vhostHttpsPort;
  final String? authToken;
  final FrpsWebServerConfig? webServer;

  const FrpsConfig({
    this.bindPort = 7000,
    this.bindAddr = "0.0.0.0",
    this.vhostHttpPort,
    this.vhostHttpsPort,
    this.authToken,
    this.webServer,
  });

  /// Generates full frps.toml configuration string
  String toTomlString() {
    final buffer = StringBuffer();

    buffer.writeln('# Generated frps.toml');
    buffer.writeln('bindAddr = "$bindAddr"');
    buffer.writeln('bindPort = $bindPort');

    if (vhostHttpPort != null) {
      buffer.writeln('vhostHTTPPort = $vhostHttpPort');
    }

    if (vhostHttpsPort != null) {
      buffer.writeln('vhostHTTPSPort = $vhostHttpsPort');
    }

    if (authToken != null && authToken!.isNotEmpty) {
      buffer.writeln('\n[auth]');
      buffer.writeln('token = "$authToken"');
    }

    if (webServer != null) {
      buffer.writeln('\n${webServer!.toTomlString()}');
    }

    return buffer.toString();
  }
}