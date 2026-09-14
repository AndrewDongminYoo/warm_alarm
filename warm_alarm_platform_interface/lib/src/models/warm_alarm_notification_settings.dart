enum WarmAlarmNotificationAuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}

final class WarmAlarmNotificationSettings {
  const WarmAlarmNotificationSettings({
    required this.authorizationStatus,
    required this.alertsEnabled,
    required this.soundsEnabled,
    required this.timeSensitiveEnabled,
  });

  final WarmAlarmNotificationAuthorizationStatus authorizationStatus;
  final bool alertsEnabled;
  final bool soundsEnabled;
  final bool? timeSensitiveEnabled;
}
