import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

void main() {
  test('WarmAlarmReadiness keeps notification settings optional', () {
    const readiness = WarmAlarmReadiness(
      level: WarmAlarmReadinessLevel.ready,
      reasons: <WarmAlarmReadinessReason>[],
    );

    expect(readiness.notificationSettings, isNull);
  });

  test('WarmAlarmNotificationSettings preserves granular iOS state', () {
    const settings = WarmAlarmNotificationSettings(
      authorizationStatus: WarmAlarmNotificationAuthorizationStatus.provisional,
      alertsEnabled: false,
      soundsEnabled: true,
      timeSensitiveEnabled: false,
    );

    expect(settings.authorizationStatus, WarmAlarmNotificationAuthorizationStatus.provisional);
    expect(settings.alertsEnabled, isFalse);
    expect(settings.soundsEnabled, isTrue);
    expect(settings.timeSensitiveEnabled, isFalse);
  });
}
