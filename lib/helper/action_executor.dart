import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:orbitx/models/automation_model.dart';

class ActionExecutor {
  static Future<dynamic> execute(
    ActionCommand cmd,
  ) async {
    switch (cmd.type) {
      case ActionType.get:
        return _get(cmd);

      case ActionType.post:
        return _post(cmd);

      case ActionType.put:
        return _put(cmd);

      case ActionType.delete:
        return _delete(cmd);

      case ActionType.notify:
        return _notify(cmd);

      case ActionType.log:
        return _log(cmd);

      case ActionType.delay:
        return _delay(cmd);

      default:
        return null;
    }
  }

  static Future<dynamic> _get(
    ActionCommand cmd,
  ) async {
    final res = await http.get(
      Uri.parse(cmd.args["url"]!),
    );

    return jsonDecode(res.body);
  }

  static Future<dynamic> _post(
    ActionCommand cmd,
  ) async {
    final res = await http.post(
      Uri.parse(cmd.args["url"]!),
      body: cmd.args["payload"] ?? "",
    );

    return res.body;
  }

  static Future<dynamic> _put(
    ActionCommand cmd,
  ) async {
    final res = await http.put(
      Uri.parse(cmd.args["url"]!),
      body: cmd.args["payload"] ?? "",
    );

    return res.body;
  }

  static Future<dynamic> _delete(
    ActionCommand cmd,
  ) async {
    final res = await http.delete(
      Uri.parse(cmd.args["url"]!),
    );

    return res.body;
  }

  static Future<void> _notify(
    ActionCommand cmd,
  ) async {
    print(
      "NOTIFY => "
      "${cmd.args["title"]} "
      "${cmd.args["body"]}",
    );

    // flutter_local_notifications
  }

  static Future<void> _log(
    ActionCommand cmd,
  ) async {
    print(cmd.args["message"]);
  }

  static Future<void> _delay(
    ActionCommand cmd,
  ) async {
    final ms = int.parse(
      cmd.args["milliseconds"] ?? "0",
    );

    await Future.delayed(
      Duration(milliseconds: ms),
    );
  }
}