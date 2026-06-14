import 'package:orbitx/models/automation_model.dart';

class AutomationReferences {
  // =========================
  // ACTIONS
  // =========================

  static const List<String> actionTypes = [
    "run",
    "get",
    "post",
    "put",
    "delete",
    "send",
    "notify",
    "mqttPublish",
    "mqttSubscribe",
    "websocket",
    "script",
    "device",
    "database",
    "file",
    "delay",
    "wait",
    "log",
  ];

  // =========================
  // ARGUMENT TYPES
  // =========================

  static const List<String> argumentTypes = [
    "url",
    "payload",
    "data",
    "headers",
    "timeout",
    "retry",
    "topic",
    "channel",
    "title",
    "body",
    "deviceId",
    "command",
    "script",
    "path",
    "query",
    "value",
  ];

  // =========================
  // PERIODICITY
  // =========================

  static const List<String> periodicities = [
    "once",
    "minutely",
    "hourly",
    "daily",
    "weekly",
    "monthly",
    "yearly",
  ];

  // =========================
  // TRIGGERS
  // =========================

  static const List<String> triggerTypes = [
    "schedule",
    "interval",
    "battery",
    "location",
    "weather",
    "network",
    "startup",
    "boot",
  ];

  // =========================
  // COMPARISON OPERATORS
  // =========================

  static const List<String> operators = [
    ">",
    "<",
    ">=",
    "<=",
    "==",
    "!=",
    "contains",
    "startsWith",
    "endsWith",
    "in",
    "notIn",
  ];

  // =========================
  // LOGICAL OPERATORS
  // =========================

  static const List<String> logicalOperators = [
    "and",
    "or",
  ];

  // =========================
  // CONTEXTS
  // =========================

  static const List<String> contexts = [
    "battery",
    "device",
    "location",
    "response",
    "network",
    "weather",
    "time",
    "storage",
    "user",
  ];

  // =========================
  // BATTERY VARIABLES
  // =========================

  static const List<String> batteryVariables = [
    "battery.percentage",
    "battery.charging",
    "battery.health",
    "battery.temperature",
    "battery.voltage",
  ];

  // =========================
  // DEVICE VARIABLES
  // =========================

  static const List<String> deviceVariables = [
    "device.id",
    "device.name",
    "device.platform",
    "device.model",
    "device.manufacturer",
    "device.orientation",
  ];

  // =========================
  // LOCATION VARIABLES
  // =========================

  static const List<String> locationVariables = [
    "point.latitude",
    "point.longitude",
    "point.altitude",
    "point.accuracy",
  ];

  // =========================
  // TIME VARIABLES
  // =========================

  static const List<String> timeVariables = [
    "time.now",
    "time.hour",
    "time.minute",
    "time.second",
    "time.day",
    "time.weekday",
    "time.month",
    "time.year",
  ];

  // =========================
  // WEATHER VARIABLES
  // =========================

  static const List<String> weatherVariables = [
    "weather.temp",
    "weather.feelsLike",
    "weather.humidity",
    "weather.pressure",
    "weather.visibility",
    "weather.windSpeed",
    "weather.windDirection",
    "weather.uvIndex",
    "weather.chanceOfRain",
    "weather.precipitation",
    "weather.description",
  ];

  // =========================
  // RESPONSE VARIABLES
  // =========================

  // Response values are dynamic and depend on the output of previous actions.
  // Only common root references should be predefined.
  static const List<String> responseVariables = [
    "response.status",
    "response.headers",
    "response.body",
  ];

  // =========================
  // NETWORK VARIABLES
  // =========================

  static const List<String> networkVariables = [
    "network.connected",
    "network.type",
    "network.ip",
    "network.ssid",
  ];

  // =========================
  // STORAGE VARIABLES
  // =========================

  static const List<String> storageVariables = [
    "storage.free",
    "storage.total",
    "storage.used",
  ];

  // =========================
  // NOTIFICATION CHANNELS
  // =========================

  static const List<String> notificationChannels = [
    "weather",
    "automation",
    "security",
    "devices",
    "system",
  ];

  // =========================
  // DEVICE COMMANDS
  // =========================

  static const List<String> deviceCommands = [
    "on",
    "off",
    "toggle",
    "lock",
    "unlock",
    "restart",
    "shutdown",
    "open",
    "close",
  ];

  // =========================
  // MQTT
  // =========================

  static const List<String> mqttQos = [
    "0",
    "1",
    "2",
  ];

  // =========================
  // FUNCTIONS
  // =========================

  static const List<String> functions = [
    "now()",
    "uuid()",
    "random()",
    "base64()",
    "json()",
    "toInt()",
    "toDouble()",
    "toString()",
  ];

  // =========================
  // VARIABLE BINDINGS
  // =========================

  static const List<String> bindingSources = [
    "point",
    "battery",
    "weather",
    "response",
    "network",
    "device",
    "time",
  ];

  // =========================
  // ALL VARIABLES
  // =========================

  static const List<String> variables = [
    ...batteryVariables,
    ...deviceVariables,
    ...locationVariables,
    ...timeVariables,
    ...weatherVariables,
    ...responseVariables,
    ...networkVariables,
    ...storageVariables,
  ];
}

class AutomationParser {
  static AutomationRule parse(
    String script, {
    String name = "Automation",
    bool enabled = true,
  }) {
    final lines = script
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final onIndex = lines.indexOf("on");
    final actIndex = lines.indexOf("act");
    final whenIndex = lines.indexOf("when");

    if (onIndex == -1 ||
        actIndex == -1 ||
        whenIndex == -1) {
      throw Exception(
        "Invalid automation script",
      );
    }

    final trigger = _parseCommand(
      lines.sublist(
        0,
        onIndex,
      ),
    );

    final startAt = DateTime.parse(
      lines[onIndex + 1],
    );

    final periodicity =
        Periodicity.values.firstWhere(
      (e) => e.name == lines[onIndex + 2],
    );

    final action = _parseCommand(
      lines.sublist(
        actIndex + 1,
        whenIndex,
      ),
    );

    final condition = lines
        .sublist(
          whenIndex + 1,
        )
        .join(" ");

    return AutomationRule(
      name: name,
      enabled: enabled,
      startAt: startAt,
      periodicity: periodicity,
      ruleJson: {
        "trigger": trigger.toJson(),
        "action": action.toJson(),
        "condition": condition,
      },
    );
  }

  static ActionCommand _parseCommand(
    List<String> lines,
  ) {
    final type = ActionType.values.firstWhere(
      (e) => e.name == lines.first,
    );

    final args = <String, String>{};

    final regex = RegExp(
      r'--([a-zA-Z0-9_]+)\s+"([^"]*)"',
    );

    for (final line in lines.skip(1)) {
      final match = regex.firstMatch(
        line,
      );

      if (match != null) {
        args[match.group(1)!] =
            match.group(2)!;
      }
    }

    return ActionCommand(
      type: type,
      args: args,
    );
  }
}
