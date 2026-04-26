final class WarmAlarmNotification {
  const WarmAlarmNotification({
    required this.title,
    required this.body,
    this.stopActionTitle,
    this.snoozeActionTitle,
  });

  final String title;
  final String body;
  final String? stopActionTitle;
  final String? snoozeActionTitle;
}
