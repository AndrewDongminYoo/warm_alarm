import 'package:warm_alarm_platform_interface/src/models/warm_alarm_readiness.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

/// The platform result of an alarm scheduling request.
/// Inspect readiness and warnings even when the request completes successfully.
final class WarmAlarmScheduleResult {
  /// Creates a result for an alarm and its readiness snapshot.
  ///
  /// The optional [warning] becomes the only entry of [warnings].
  /// Use [WarmAlarmScheduleResult.withWarnings] to report several warnings.
  const WarmAlarmScheduleResult({
    required this.alarmId,
    required this.readiness,
    WarmAlarmWarning? warning,
  }) : _warning = warning,
       _warnings = const <WarmAlarmWarning>[];

  /// Creates a result with a snapshot of every reported warning.
  /// Copies [warnings] so later changes to the supplied list cannot change this result.
  WarmAlarmScheduleResult.withWarnings({
    required this.alarmId,
    required this.readiness,
    required List<WarmAlarmWarning> warnings,
  }) : _warning = null,
       _warnings = List<WarmAlarmWarning>.unmodifiable(warnings);

  /// The identifier associated with the scheduling request.
  final int alarmId;

  /// Readiness reported by the platform while handling this request.
  final WarmAlarmReadiness readiness;

  final WarmAlarmWarning? _warning;
  final List<WarmAlarmWarning> _warnings;

  /// The first scheduling warning, or null when [warnings] is empty.
  /// The warning may itself have a null code.
  /// A null warning does not guarantee that every platform-specific option was applied.
  WarmAlarmWarning? get warning => _warning ?? (_warnings.isEmpty ? null : _warnings.first);

  /// Every scheduling warning, in the order the platform detected them.
  /// The list is empty when the platform reports no warning, and it cannot be modified.
  /// An empty list does not guarantee that every platform-specific option was applied.
  List<WarmAlarmWarning> get warnings =>
      _warning == null ? _warnings : List<WarmAlarmWarning>.unmodifiable(<WarmAlarmWarning>[_warning]);
}
