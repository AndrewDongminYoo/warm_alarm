import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

const _readiness = WarmAlarmReadiness(
  level: WarmAlarmReadinessLevel.ready,
  reasons: <WarmAlarmReadinessReason>[],
);

const _wakeCheckWarning = WarmAlarmWarning(
  message: 'Wake-check is not supported on iOS.',
  code: WarmAlarmWarningCode.unsupportedWakeCheck,
);

const _nativeWarning = WarmAlarmWarning(message: 'Time Sensitive notifications are disabled.');

void main() {
  group('WarmAlarmScheduleResult warnings', () {
    test('reports no warning when the platform returns none', () {
      const result = WarmAlarmScheduleResult(alarmId: 1, readiness: _readiness);

      expect(result.warnings, isEmpty);
      expect(result.warning, isNull);
    });

    test('exposes a legacy single warning as the only list entry', () {
      const result = WarmAlarmScheduleResult(
        alarmId: 1,
        readiness: _readiness,
        warning: _nativeWarning,
      );

      expect(result.warnings, <WarmAlarmWarning>[_nativeWarning]);
      expect(result.warning, same(_nativeWarning));
    });

    test('exposes one listed warning through the single field', () {
      final result = WarmAlarmScheduleResult.withWarnings(
        alarmId: 1,
        readiness: _readiness,
        warnings: <WarmAlarmWarning>[_wakeCheckWarning],
      );

      expect(result.warnings, <WarmAlarmWarning>[_wakeCheckWarning]);
      expect(result.warning, same(_wakeCheckWarning));
    });

    test('reports no warning for an explicitly empty list', () {
      final result = WarmAlarmScheduleResult.withWarnings(
        alarmId: 1,
        readiness: _readiness,
        warnings: List<WarmAlarmWarning>.empty(),
      );

      expect(result.warnings, isEmpty);
      expect(result.warning, isNull);
    });

    test('keeps several warnings in detection order and the first as the single field', () {
      final result = WarmAlarmScheduleResult.withWarnings(
        alarmId: 1,
        readiness: _readiness,
        warnings: <WarmAlarmWarning>[_wakeCheckWarning, _nativeWarning],
      );

      expect(result.warnings, <WarmAlarmWarning>[_wakeCheckWarning, _nativeWarning]);
      expect(result.warning, same(_wakeCheckWarning));
      expect(result.warnings.last.code, isNull);
    });

    test('returns a list that callers cannot modify', () {
      final result = WarmAlarmScheduleResult.withWarnings(
        alarmId: 1,
        readiness: _readiness,
        warnings: <WarmAlarmWarning>[_nativeWarning],
      );

      expect(() => result.warnings.add(_wakeCheckWarning), throwsUnsupportedError);
      expect(
        () => const WarmAlarmScheduleResult(
          alarmId: 1,
          readiness: _readiness,
          warning: _nativeWarning,
        ).warnings.clear(),
        throwsUnsupportedError,
      );
    });

    test('keeps the result stable when the caller reuses its warning accumulator', () {
      final accumulator = <WarmAlarmWarning>[_wakeCheckWarning, _nativeWarning];
      final result = WarmAlarmScheduleResult.withWarnings(
        alarmId: 1,
        readiness: _readiness,
        warnings: accumulator,
      );

      accumulator
        ..clear()
        ..add(_nativeWarning);

      expect(result.warnings, <WarmAlarmWarning>[_wakeCheckWarning, _nativeWarning]);
      expect(result.warning, same(_wakeCheckWarning));
    });
  });
}
