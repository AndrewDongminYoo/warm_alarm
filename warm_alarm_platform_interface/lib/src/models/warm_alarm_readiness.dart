final class WarmAlarmReadiness {
  const WarmAlarmReadiness({
    required this.level,
    required this.reasons,
  });

  final WarmAlarmReadinessLevel level;
  final List<WarmAlarmReadinessReason> reasons;
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
