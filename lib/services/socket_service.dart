import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orbitx/dto/packet_dto.dart';



class SocketService{
  late Socket? _socket;
  late StreamSubscription<Uint8List>? _subs;
  Future<bool> connect(String address, int port)async {
    try{
    _socket = await Socket.connect(address, port, timeout: const Duration(seconds: 5));
    return true;
    }catch(err){
      return false;
    }
  }

  StreamSubscription<Uint8List>? listen(Function(Packet) callback){
    _subs=_socket?.listen((data)=>callback(Packet.fromBytes(data)));
    return _subs;
  }

  void send(Packet packet){
    _socket?.add(packet.toBytes());
  }

  void destroy(){
    _subs?.cancel();
    _socket?.destroy();
    _socket=null;
  }
}