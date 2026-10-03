/// A scheduling limitation returned alongside an alarm result.
/// A single message can include both an unsupported-option warning and native scheduling details.
final class WarmAlarmWarning {
  /// Creates a warning with an optional code for programmatic handling.
  const WarmAlarmWarning({
    required this.message,
    this.code,
  });

  /// Human-readable details, including any preserved native warning.
  final String message;

  /// The classified warning, or null for a warning that has no structured code.
  /// A null code does not mean there is no warning.
  final WarmAlarmWarningCode? code;
}

/// Scheduling warnings that currently have a stable programmatic identifier.
enum WarmAlarmWarningCode {
  /// The requested wake-check option was ignored because the platform does not support it.
  unsupportedWakeCheck,
}

final class WarmAlarmFailure {
  const WarmAlarmFailure({
    required this.code,
    this.message,
  });

  final WarmAlarmFailureCode code;
  final String? message;
}

/// How a platform supports a feature under its current runtime configuration.
enum WarmAlarmSupportStatus {
  /// The feature is supported; current permissions and readiness still need inspection.
  supported,

  /// The feature has implementation or platform restrictions.
  limited,

  /// The implementation cannot provide the feature.
  unsupported,

  /// The implementation has not established the feature's support status.
  unknown,
}

enum WarmAlarmFailureCode {
  unknown,
  invalidArguments,
  permissionDenied,
  exactAlarmUnavailable,
  notificationUnavailable,
  audioFileNotFound,
  audioPlaybackFailed,
  schedulingFailed,
  platformInternalError,
}
