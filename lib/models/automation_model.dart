class AutomationDraft {
  String? action;
  String? periodicity;
  DateTime? startAt;

  final List<ArgumentDraft> arguments = [];

  String? conditionVariable;
  String? conditionOperator;
  String? conditionValue;
}

class ArgumentDraft {
  String? key;
  String? value;

  ArgumentDraft({
    this.key,
    this.value,
  });
}


enum ActionType {
  get,
  post,
  put,
  delete,
  notify,
  mqttPublish,
  device,
  delay,
  log,
}

enum Periodicity {
  once,
  minutely,
  hourly,
  daily,
  weekly,
  monthly,
  yearly
}

class AutomationRule {
  final int? id;

  final String name;

  final bool enabled;

  final DateTime startAt;

  final Periodicity periodicity;

  final Map<String, dynamic> ruleJson;

  AutomationRule({
    this.id,
    required this.name,
    required this.enabled,
    required this.startAt,
    required this.periodicity,
    required this.ruleJson,
  });

  factory AutomationRule.fromMap(
    Map<String, dynamic> map,
  ) {
    return AutomationRule(
      id: map["id"],
      name: map["name"],
      enabled: map["enabled"] == 1,
      startAt: DateTime.parse(
        map["start_at"],
      ),
      periodicity:
          Periodicity.values.firstWhere(
        (e) =>
            e.name ==
            map["periodicity"],
      ),
      ruleJson: map["rule_json"],
    );
  }
}

class ActionCommand {
  final ActionType type;
  final Map<String, String> args;

  ActionCommand({
    required this.type,
    required this.args,
  });

  factory ActionCommand.fromJson(
    Map<String, dynamic> json,
  ) {
    return ActionCommand(
      type: ActionType.values.firstWhere(
        (e) => e.name == json["type"],
      ),
      args: Map<String, String>.from(
        json["args"] ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "type": type.name,
      "args": args,
    };
  }
}