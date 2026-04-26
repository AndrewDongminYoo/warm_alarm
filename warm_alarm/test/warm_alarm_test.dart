import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm/warm_alarm.dart';

class MockWarmAlarmPlatform extends Mock with MockPlatformInterfaceMixin implements WarmAlarmPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarm, () {
    late WarmAlarmPlatform warmAlarmPlatform;

    setUp(() {
      warmAlarmPlatform = MockWarmAlarmPlatform();
      WarmAlarmPlatform.instance = warmAlarmPlatform;
    });

    test('scheduleAlarm forwards to platform and returns typed result', () async {
      final schedule = WarmAlarmSchedule(
        id: 1,
        scheduledAt: DateTime(2026, 4, 27, 7),
        notification: const WarmAlarmNotification(
          title: 'Wake up',
          body: 'Now',
        ),
        audio: const WarmAlarmAudio(filePath: '/tmp/voice.m4a'),
      );

      const result = WarmAlarmScheduleResult(
        alarmId: 1,
        readiness: WarmAlarmReadiness(
          level: WarmAlarmReadinessLevel.ready,
          reasons: <WarmAlarmReadinessReason>[],
        ),
      );

      when(
        () => warmAlarmPlatform.scheduleAlarm(schedule),
      ).thenAnswer((_) async => result);

      expect(await WarmAlarm.scheduleAlarm(schedule), result);
    });
  });
}
