import 'package:warm_alarm_platform_interface/src/models/warm_alarm_permission_state.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_readiness.dart';

/// How the platform handled a readiness remediation action.
enum WarmAlarmRemediationStatus {
  /// The action started or completed.
  /// Inspect the returned state because a user can decline the request.
  completed,

  /// The action cannot start in the current platform state.
  unavailable,

  /// The platform does not support the requested action.
  unsupported,
}

/// The result of a user-initiated readiness remediation action.
final class WarmAlarmRemediationResult {
  const WarmAlarmRemediationResult({
    required this.status,
    required this.permissionState,
    required this.readiness,
  });

  /// How the platform handled the action.
  final WarmAlarmRemediationStatus status;

  /// The permission state when the action returns.
  final WarmAlarmPermissionState permissionState;

  /// The readiness snapshot when the action returns.
  final WarmAlarmReadiness readiness;
}
