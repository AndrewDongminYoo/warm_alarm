import 'package:warm_alarm_platform_interface/src/models/warm_alarm_notification_settings.dart';

final class WarmAlarmReadiness {
  const WarmAlarmReadiness({
    required this.level,
    required this.reasons,
    this.notificationSettings,
  });

  final WarmAlarmReadinessLevel level;
  final List<WarmAlarmReadinessReason> reasons;
  final WarmAlarmNotificationSettings? notificationSettings;
}

enum WarmAlarmReadinessLevel {
  ready,
  limited,
  blocked,
  unsupported,
}

enum WarmAlarmReadinessReason {
  notificationPermissionDenied,
  exactAlarmPermissionDenied,
  fullScreenPermissionDenied,
  backgroundExecutionLimited,
  backgroundAudioLimited,
  platformUnsupported,
  batteryOptimizationMayDelay,
  unknown,
}
