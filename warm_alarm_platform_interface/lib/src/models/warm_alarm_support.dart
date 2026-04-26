final class WarmAlarmWarning {
  const WarmAlarmWarning({
    required this.message,
  });

  final String message;
}

final class WarmAlarmFailure {
  const WarmAlarmFailure({
    required this.code,
    this.message,
  });

  final WarmAlarmFailureCode code;
  final String? message;
}

enum WarmAlarmSupportStatus {
  supported,
  limited,
  unsupported,
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
