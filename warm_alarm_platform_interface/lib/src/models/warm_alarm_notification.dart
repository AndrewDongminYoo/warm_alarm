final class WarmAlarmNotification {
  const WarmAlarmNotification({
    required this.title,
    required this.body,
    this.stopActionTitle,
    this.snoozeActionTitle,
    this.androidIcon,
    this.androidIconColor,
    this.keepNotificationAfterAlarmEnds = false,
  });

  final String title;
  final String body;
  final String? stopActionTitle;
  final String? snoozeActionTitle;
  final String? androidIcon;
  final int? androidIconColor;
  final bool keepNotificationAfterAlarmEnds;
}
