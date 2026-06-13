import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:orbitx/dto/packet_dto.dart';
import 'package:orbitx/services/socket_service.dart';

class ActionService {
  static Map<String, Function(List<String>)> availableActions = {
    "connect": (List<String> parts) async {
      if (parts[0] == 'termux') {
        debugPrint("Starting Termux\n\n\n");
        bool running = await service.connect('127.0.0.1', 54321);
        if (running) {
          return true;
        } else {
          await InstalledApps.startApp("com.termux").then(
            (value) => {
              Timer(const Duration(seconds: 1000), () {
                service.connect('127.0.0.1', 54321);
                InstalledApps.startApp('com.shiva2232.orbitx');
              }),
            },
          );
        }
        return true;
      } else {
        debugPrint("Starting Termux\n\n\n");
        InstalledApps.startApp(parts[0]);
      }
    },
    "run": (List<String> parts) {
      debugPrint("Starting ${parts[0]}\n\n\n");
      InstalledApps.startApp(parts[0]);
      return Future.value(true);
    },
    "snd": (List<String> parts) {
      String safeGet(List<String> list, int index) {
        return index < list.length ? list[index] : '';
      }

      List<String> message = parts.join(' ').split(':');
      Packet packet = Packet(
        command: safeGet(message, 0),
        success: safeGet(message, 1),
        failure: safeGet(message, 2),
        output: '',
        callback: safeGet(message, 3),
        error: safeGet(message, 4),
      );
      service.send(packet);
      return Future.value(true);
    },
  };

  static Future<bool> start(String command, context) async {
    final parts = command.split(' ');
    debugPrint(parts.join() + command + "\n\n\n\n");
    if (ActionService.availableActions[parts[0]] != null) {
      final bool status = await availableActions[parts[0]]?.call(
        parts.sublist(1),
      );
      return status;
    } else {
      try {
        final ProcessResult value = await Process.run(
          parts[0],
          parts.sublist(1),
          runInShell: true,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value.stdout,
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString(),
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
    return await availableActions[parts[0]]?.call(parts.sublist(1));
  }
}
