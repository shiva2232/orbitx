
import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:orbitx/dto/packet_dto.dart';
import 'package:orbitx/services/socket_service.dart';

class ActionService {
  static Map<String, Function(List<String>)> availableActions = {
    "connect": (List<String>  parts) {
      if(parts[0]=='termux'){
        debugPrint("Starting Termux\n\n\n");
        InstalledApps.startApp("com.termux");
        return service.connect('127.0.0.1', 54321);
      }
    },
    "snd": (List<String> parts){
      List<String> message=parts.join('').split(':');
      Packet packet=Packet(command: message[0], success: message[1], failure: message[2]);
      service.send(packet);
      return Future.value(true);
    }
  };

  static Future<bool> start(String command){
    final parts=command.split(' ');
    return availableActions[parts[0]]?.call(parts.sublist(1));
  }
  
}