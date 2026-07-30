import 'dart:convert';
import 'dart:io';

import 'package:orbitx/models/proxies_model.dart';

Future<ProxyResponse> getTcpProxies(String addr) async {
  try {
    final socket = await Socket.connect(addr, 7500);

    final auth = base64.encode(utf8.encode("admin:password"));

    socket.write(
      "GET /api/proxy/tcp HTTP/1.1\r\n"
      "Host: 10.0.0.2\r\n"
      "Authorization: Basic $auth\r\n"
      "Connection: close\r\n"
      "\r\n",
    );

    final response = await utf8.decoder.bind(socket).join();

    socket.destroy();

    final body = response.split("\r\n\r\n").last;

    return ProxyResponse.fromJson(jsonDecode(body));
  } catch (err) {
    return ProxyResponse(proxies: List.empty());
  }
}
