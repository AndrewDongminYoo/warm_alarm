import 'package:warm_alarm_platform_interface/src/models/warm_alarm_notification_settings.dart';

/// The platform's current readiness assessment and the reasons behind it.
/// A ready snapshot does not guarantee future delivery or inspect every operating-system restriction.
final class WarmAlarmReadiness {
  /// Creates a readiness snapshot with optional detailed notification settings.
  const WarmAlarmReadiness({
    required this.level,
    required this.reasons,
    this.notificationSettings,
  });

  /// The platform's overall assessment at the time of the query.
  final WarmAlarmReadinessLevel level;

  /// The detected permissions or platform limits affecting readiness.
  /// Some reasons describe limits that cannot be removed through settings.
  final List<WarmAlarmReadinessReason> reasons;

  /// Detailed notification settings when the platform exposes them.
  final WarmAlarmNotificationSettings? notificationSettings;
}

/// The overall readiness reported by a platform's current checks.
enum WarmAlarmReadinessLevel {
  /// No blocking or limiting condition was detected by the current checks.
  ready,

  /// Scheduling is subject to detected permissions or platform limitations.
  limited,

  /// A detected condition prevents delivery through the assessed backend.
  blocked,

  /// The platform implementation does not support alarm delivery.
  unsupported,
}

/// A detected condition that explains a readiness assessment.
/// Implementations report the reasons they can observe; not every reason has a settings action.
enum WarmAlarmReadinessReason {
  /// Notification authorization is missing for the notification backend.
  notificationPermissionDenied,

  /// Exact-alarm authorization is missing, including iOS AlarmKit authorization.
  exactAlarmPermissionDenied,

  /// Permission to present a full-screen alarm intent is missing.
  fullScreenPermissionDenied,

  /// The platform restricts background execution.
  backgroundExecutionLimited,

  /// The platform reports a restriction on background audio playback.
  backgroundAudioLimited,

  /// No supported alarm implementation is available for the platform.
  platformUnsupported,

  /// The implementation reports that battery policies may delay delivery.
  batteryOptimizationMayDelay,

  /// The implementation cannot classify the current readiness condition.
  unknown,
}
