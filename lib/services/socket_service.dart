import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:orbitx/dto/packet_dto.dart';

class SocketService {
  Socket? _socket;
  late StreamSubscription<Uint8List>? _subs;
  bool _connected = false;

  final StreamController<bool> _controller = StreamController.broadcast();

  Future<bool> connect(String address, int port) async {
    try {
      _socket = await Socket.connect(address, port);

      _connected = true;
      _controller.add(true);

      return true;
    } catch (e) {
      _connected = false;
      _controller.add(false);
      _socket = null;
      return false;
    }
  }

  Stream<bool> get listening {
    return _controller.stream;
  }

  StreamSubscription<Uint8List>? listen(Function(Packet) callback) {
    String buffer = "";
    _subs = _socket!.listen(
      (data) {
        buffer += utf8.decode(data);

        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');

          final line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);

          if (line.trim().isEmpty) continue;

          final packet = Packet.fromMap(jsonDecode(line));
          callback(packet);
        }
      },
      onDone: () {
        _connected = false;
        _controller.add(false);
        _socket = null;
      },
      onError: (error) {
        _connected = false;
        _controller.add(false);
        _socket = null;
      },
      cancelOnError: true,
    );
    return _subs;
  }

  void send(Packet packet) {
    _socket?.add(utf8.encode("${jsonEncode(packet.toMap())}\n"));
  }

  bool get isRunning => _connected;

  void destroy() {
    _connected = false;
    _controller.add(false);

    _subs?.cancel();
    _socket?.destroy();
    _socket = null;
  }
}

final SocketService service = SocketService();
