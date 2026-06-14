import 'variable_context.dart';

class ConditionEvaluator {
  static bool evaluate(
    String expression,
    AutomationContext context,
  ) {
    expression = expression.trim();

    final regex = RegExp(
      r'(.+?)\s*(>=|<=|==|!=|>|<)\s*(.+)',
    );

    final match =
        regex.firstMatch(expression);

    if (match == null) {
      return false;
    }

    final left =
        context.getValue(match.group(1)!.trim());

    final op = match.group(2)!;

    final right =
        double.tryParse(match.group(3)!) ??
            match.group(3);

    if (left is num && right is num) {
      switch (op) {
        case ">":
          return left > right;

        case "<":
          return left < right;

        case ">=":
          return left >= right;

        case "<=":
          return left <= right;

        case "==":
          return left == right;

        case "!=":
          return left != right;
      }
    }

    return false;
  }
}