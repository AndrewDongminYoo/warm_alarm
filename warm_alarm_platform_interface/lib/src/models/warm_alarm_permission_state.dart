final class WarmAlarmPermissionState {
  const WarmAlarmPermissionState({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
    required this.fullScreenIntentGranted,
  });

  final bool notificationsGranted;
  final bool exactAlarmGranted;
  final bool fullScreenIntentGranted;
}
