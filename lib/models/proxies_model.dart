class ProxyResponse {
  final List<Proxy> proxies;

  ProxyResponse({
    required this.proxies,
  });

  factory ProxyResponse.fromJson(Map<String, dynamic> json) {
    return ProxyResponse(
      proxies: (json["proxies"] as List)
          .map((e) => Proxy.fromJson(e))
          .toList(),
    );
  }
}

class Proxy {
  final String name;
  final ProxyConf conf;
  final String clientID;
  final int todayTrafficIn;
  final int todayTrafficOut;
  final int curConns;
  final String lastStartTime;
  final String lastCloseTime;
  final String status;

  Proxy({
    required this.name,
    required this.conf,
    required this.clientID,
    required this.todayTrafficIn,
    required this.todayTrafficOut,
    required this.curConns,
    required this.lastStartTime,
    required this.lastCloseTime,
    required this.status,
  });

  factory Proxy.fromJson(Map<String, dynamic> json) {
    return Proxy(
      name: json["name"],
      conf: ProxyConf.fromJson(json["conf"]),
      clientID: json["clientID"],
      todayTrafficIn: json["todayTrafficIn"],
      todayTrafficOut: json["todayTrafficOut"],
      curConns: json["curConns"],
      lastStartTime: json["lastStartTime"],
      lastCloseTime: json["lastCloseTime"],
      status: json["status"],
    );
  }
}

class ProxyConf {
  final String name;
  final String type;
  final String localIP;
  final int remotePort;

  ProxyConf({
    required this.name,
    required this.type,
    required this.localIP,
    required this.remotePort,
  });

  factory ProxyConf.fromJson(Map<String, dynamic> json) {
    return ProxyConf(
      name: json["name"],
      type: json["type"],
      localIP: json["localIP"],
      remotePort: json["remotePort"],
    );
  }
}