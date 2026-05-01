final class WarmAlarmWakeCheck {
  const WarmAlarmWakeCheck({
    required this.checkDelay,
    this.retriggerDelay,
    this.maxRetriggers = 1,
  });

  final Duration checkDelay;
  final Duration? retriggerDelay;
  final int? maxRetriggers;
}
