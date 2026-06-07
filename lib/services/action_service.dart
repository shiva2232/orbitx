
import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';

class ActionService {
  Map<String, Function(List<String>)> availableActions = {
    "connect": (List<String>  parts) {
      if(parts[0]=='termux'){
        debugPrint("Starting Termux\n\n\n");
        InstalledApps.startApp("com.termux");
      }
    },
  };
  void performAction(String action) {
    // Implement action handling logic here
    print("Performing action: $action");
  }

  Future<bool> start(String command){
    final parts=command.split(' ');
    availableActions[parts[0]]?.call(parts.sublist(1));
    return Future.value(true);
  }
  
}