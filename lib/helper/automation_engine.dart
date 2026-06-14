import '../models/automation_model.dart';
import 'action_executor.dart';
import 'condition_evaluator.dart';
import 'variable_context.dart';

class AutomationEngine {
  static Future<void> run(
    AutomationRule rule,
    AutomationContext context,
  ) async {
    try {
      if (!rule.enabled) {
        return;
      }

      final trigger = ActionCommand.fromJson(
        Map<String, dynamic>.from(
          rule.ruleJson["trigger"],
        ),
      );

      final action = ActionCommand.fromJson(
        Map<String, dynamic>.from(
          rule.ruleJson["action"],
        ),
      );

      final condition =
          rule.ruleJson["condition"]
              ?.toString() ??
          "";

      final response =
          await ActionExecutor.execute(
        trigger,
      );

      final runtimeValues =
          <String, dynamic>{
        ...context.values,
      };

      if (response != null) {
        runtimeValues["response"] =
            response;

        runtimeValues[
                "response.body"] =
            response;

        if (response is Map) {
          _flattenMap(
            response,
            "response",
            runtimeValues,
          );
        }
      }

      final runtimeContext =
          AutomationContext(
        runtimeValues,
      );

      bool shouldRun = true;

      if (condition
          .trim()
          .isNotEmpty) {
        shouldRun =
            ConditionEvaluator
                .evaluate(
          condition,
          runtimeContext,
        );
      }

      if (!shouldRun) {
        return;
      }

      await ActionExecutor.execute(
        action,
      );
    } catch (e, st) {
      print(
        "Automation execution failed",
      );

      print(e);

      print(st);
    }
  }

  static void _flattenMap(
    Map map,
    String prefix,
    Map<String, dynamic> output,
  ) {
    map.forEach((key, value) {
      final path =
          "$prefix.$key";

      output[path] = value;

      if (value is Map) {
        _flattenMap(
          value,
          path,
          output,
        );
      }
    });
  }
}