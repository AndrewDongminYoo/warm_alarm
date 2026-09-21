/// The alarm state displayed by a host-provided Live Activity widget.
enum WarmAlarmLiveActivityStatus { scheduled, ringing, snoozed }

/// Content for an opt-in iOS Live Activity.
/// This does not schedule an alarm or start audio playback.
final class WarmAlarmLiveActivityState {
  const WarmAlarmLiveActivityState({
    required this.alarmId,
    required this.title,
    required this.status,
    this.scheduledAt,
  });

  final int alarmId;
  final String title;
  final WarmAlarmLiveActivityStatus status;

  /// The next occurrence, or null when no next occurrence should be displayed.
  final DateTime? scheduledAt;
}

/// The outcome of a Live Activity operation.
enum WarmAlarmLiveActivityResultStatus {
  completed,

  /// The operating system or host has no configured integration.
  unsupported,

  /// The user has disabled Live Activities for this host.
  disabled,

  /// No active Live Activity has the supplied identifier.
  notFound,
}

final class WarmAlarmLiveActivityResult {
  const WarmAlarmLiveActivityResult({required this.status, this.activityId});

  final WarmAlarmLiveActivityResultStatus status;

  /// The ActivityKit identifier returned by a successful start.
  final String? activityId;
}
