import 'package:warm_alarm_platform_interface/src/models/warm_alarm_readiness.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

/// The platform result of an alarm scheduling request.
/// Inspect readiness and warnings even when the request completes successfully.
final class WarmAlarmScheduleResult {
  /// Creates a result for an alarm and its readiness snapshot.
  const WarmAlarmScheduleResult({
    required this.alarmId,
    required this.readiness,
    this.warning,
  });

  /// The identifier associated with the scheduling request.
  final int alarmId;

  /// Readiness reported by the platform while handling this request.
  final WarmAlarmReadiness readiness;

  /// An optional scheduling warning, which may itself have a null code.
  /// A null warning does not guarantee that every platform-specific option was applied.
  final WarmAlarmWarning? warning;
}
