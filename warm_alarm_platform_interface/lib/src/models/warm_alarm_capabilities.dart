import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

/// A runtime snapshot of support for each alarm feature.
/// Support can depend on host configuration and authorization; it is not a delivery guarantee.
/// Query readiness separately to inspect current permissions and platform limits.
final class WarmAlarmCapabilities {
  /// Creates a snapshot from the support status reported for each feature.
  const WarmAlarmCapabilities({
    required this.exactScheduling,
    required this.notificationScheduling,
    required this.backgroundAudioPlayback,
    required this.fullScreenPresentation,
    required this.wakeCheck,
    required this.liveActivity,
  });

  /// Support for exact scheduling, including the configured iOS AlarmKit backend.
  final WarmAlarmSupportStatus exactScheduling;

  /// Support for scheduling notifications, separate from notification permission.
  final WarmAlarmSupportStatus notificationScheduling;

  /// Support for custom audio playback while the app is in the background.
  final WarmAlarmSupportStatus backgroundAudioPlayback;

  /// Support for presenting the app through a full-screen alarm intent.
  /// The iOS AlarmKit system UI does not count as a Flutter full-screen presentation.
  final WarmAlarmSupportStatus fullScreenPresentation;

  /// Support for checking whether the user is awake and retriggering an alarm.
  final WarmAlarmSupportStatus wakeCheck;

  /// Support for custom Live Activities, separate from AlarmKit countdown presentation.
  final WarmAlarmSupportStatus liveActivity;
}
