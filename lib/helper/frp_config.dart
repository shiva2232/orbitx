enum ProxyType { tcp, udp, http, https, stcp, xtcp }

extension ProxyTypeExtension on ProxyType {
  String get value => toString().split('.').last;
}

class FrpProxyConfig {
  final String name;
  final ProxyType type;
  final String localIp;
  final int localPort;
  final int? remotePort;
  final List<String>? customDomains;
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

  String toTomlString() {
    final buffer = StringBuffer();
    buffer.writeln('[[proxies]]');
    buffer.writeln('name = "$name"');
    buffer.writeln('type = "${type.value}"');
    buffer.writeln('localIP = "$localIp"');
    buffer.writeln('localPort = $localPort');
    if (remotePort != null) buffer.writeln('remotePort = $remotePort');
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

  String toTomlString() {
    final buffer = StringBuffer();
    buffer.writeln('serverAddr = "$serverAddr"');
    buffer.writeln('serverPort = $serverPort');
    if (authToken != null && authToken!.isNotEmpty) {
      buffer.writeln('\n[auth]');
      buffer.writeln('method = "token"');
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

  String toTomlString() {
    final buffer = StringBuffer();
    buffer.writeln('bindAddr = "$bindAddr"');
    buffer.writeln('bindPort = $bindPort');
    if (vhostHttpPort != null) buffer.writeln('vhostHTTPPort = $vhostHttpPort');
    if (vhostHttpsPort != null) buffer.writeln('vhostHTTPSPort = $vhostHttpsPort');
    // no need
      buffer.writeln('webServer.addr = "0.0.0.0"');
      buffer.writeln('webServer.port = 7500');
      buffer.writeln('webServer.user = "admin"');
      buffer.writeln('webServer.password = "password"');
    if (authToken != null && authToken!.isNotEmpty) {
      buffer.writeln('\n[auth]');
      buffer.writeln('method = "token"');
      buffer.writeln('token = "$authToken"');
    }
    if (webServer != null) buffer.writeln('\n${webServer!.toTomlString()}');
    return buffer.toString();
  }
}
