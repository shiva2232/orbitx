import 'package:orbitx/models/automation_model.dart';

class ScheduleEvaluator {
  static bool shouldRunNow(
    AutomationRule rule,
    DateTime now,
  ) {
    final start =
        rule.startAt;

    switch (
        rule.periodicity) {
      case Periodicity.once:
        return _sameMinute(
          start,
          now,
        );

      case Periodicity.minutely:
        return true;

      case Periodicity.hourly:
        return now.minute ==
            start.minute;

      case Periodicity.daily:
        return now.hour ==
                start.hour &&
            now.minute ==
                start.minute;

      case Periodicity.weekly:
        return now.weekday ==
                start.weekday &&
            now.hour ==
                start.hour &&
            now.minute ==
                start.minute;

      case Periodicity.monthly:
        return now.day ==
                start.day &&
            now.hour ==
                start.hour &&
            now.minute ==
                start.minute;

      case Periodicity.yearly:
        return now.month ==
                start.month &&
            now.day ==
                start.day &&
            now.hour ==
                start.hour &&
            now.minute ==
                start.minute;
    }
  }

  static bool _sameMinute(
    DateTime a,
    DateTime b,
  ) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }
}