
class AutomationContext {
  final Map<String, dynamic> values;

  AutomationContext(this.values);

  dynamic getValue(String path) {
    return values[path];
  }
}