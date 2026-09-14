import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_example/main.dart' as example;

void main() {
  test('denied authorization selects notification permission remediation', () {
    final readiness = _readiness(
      authorizationStatus: WarmAlarmNotificationAuthorizationStatus.denied,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.notificationPermissionDenied,
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      ],
    );

    expect(
      example.readinessRemediationReason(readiness),
      WarmAlarmReadinessReason.notificationPermissionDenied,
    );
  });

  test('undetermined authorization selects notification permission remediation', () {
    final readiness = _readiness(
      authorizationStatus: WarmAlarmNotificationAuthorizationStatus.notDetermined,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.notificationPermissionDenied,
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      ],
    );

    expect(
      example.readinessRemediationReason(readiness),
      WarmAlarmReadinessReason.notificationPermissionDenied,
    );
  });

  test('provisional authorization prioritizes notification settings', () {
    final readiness = _readiness(
      authorizationStatus: WarmAlarmNotificationAuthorizationStatus.provisional,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.exactAlarmPermissionDenied,
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      ],
    );

    expect(
      example.readinessRemediationReason(readiness),
      WarmAlarmReadinessReason.backgroundExecutionLimited,
    );
  });

  for (final disabledSetting in <String>['alerts', 'sounds', 'timeSensitive']) {
    test('disabled $disabledSetting selects notification settings', () {
      final readiness = _readiness(
        alertsEnabled: disabledSetting != 'alerts',
        soundsEnabled: disabledSetting != 'sounds',
        timeSensitiveEnabled: disabledSetting != 'timeSensitive',
        reasons: <WarmAlarmReadinessReason>[WarmAlarmReadinessReason.backgroundExecutionLimited],
      );

      expect(
        example.readinessRemediationReason(readiness),
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      );
    });
  }

  test('healthy notification settings skip background-only remediation', () {
    final readiness = _readiness(
      reasons: <WarmAlarmReadinessReason>[WarmAlarmReadinessReason.backgroundExecutionLimited],
    );

    expect(example.readinessRemediationReason(readiness), isNull);
  });

  test('unavailable time sensitive setting is not treated as disabled', () {
    final readiness = _readiness(
      timeSensitiveEnabled: null,
      reasons: <WarmAlarmReadinessReason>[WarmAlarmReadinessReason.backgroundExecutionLimited],
    );

    expect(example.readinessRemediationReason(readiness), isNull);
  });

  test('healthy notification settings preserve the first other reason', () {
    final readiness = _readiness(
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.backgroundExecutionLimited,
        WarmAlarmReadinessReason.exactAlarmPermissionDenied,
      ],
    );

    expect(
      example.readinessRemediationReason(readiness),
      WarmAlarmReadinessReason.exactAlarmPermissionDenied,
    );
  });
}

WarmAlarmReadiness _readiness({
  required List<WarmAlarmReadinessReason> reasons,
  WarmAlarmNotificationAuthorizationStatus authorizationStatus = WarmAlarmNotificationAuthorizationStatus.authorized,
  bool alertsEnabled = true,
  bool soundsEnabled = true,
  bool? timeSensitiveEnabled = true,
}) {
  return WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.limited,
    reasons: reasons,
    notificationSettings: WarmAlarmNotificationSettings(
      authorizationStatus: authorizationStatus,
      alertsEnabled: alertsEnabled,
      soundsEnabled: soundsEnabled,
      timeSensitiveEnabled: timeSensitiveEnabled,
    ),
  );
}
