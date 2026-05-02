import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelWarmAlarm', () {
    late MethodChannelWarmAlarm methodChannelWarmAlarm;
    final log = <MethodCall>[];

    setUp(() {
      methodChannelWarmAlarm = MethodChannelWarmAlarm();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelWarmAlarm.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'getReadiness':
              return <String, Object?>{
                'level': 'unsupported',
                'reasons': <String>['platformUnsupported'],
              };
            default:
              return null;
          }
        },
      );
    });

    tearDown(log.clear);

    test(
      'getReadiness returns a typed unsupported stub without channel traffic',
      () async {
        final readiness = await methodChannelWarmAlarm.getReadiness();
        expect(log, isEmpty);
        expect(readiness.level, WarmAlarmReadinessLevel.unsupported);
        expect(
          readiness.reasons,
          equals(<WarmAlarmReadinessReason>[
            WarmAlarmReadinessReason.platformUnsupported,
          ]),
        );
      },
    );

    test('cancelAlarm completes without channel traffic', () async {
      await expectLater(methodChannelWarmAlarm.cancelAlarm(1), completes);
      expect(log, isEmpty);
    });

    test('cancelAllAlarms completes without channel traffic', () async {
      await expectLater(methodChannelWarmAlarm.cancelAllAlarms(), completes);
      expect(log, isEmpty);
    });

    test('events returns empty stream', () {
      expect(methodChannelWarmAlarm.events, isA<Stream<WarmAlarmEvent>>());
    });

    test('getCapabilities returns stub with all unknown statuses', () async {
      final caps = await methodChannelWarmAlarm.getCapabilities();
      expect(caps.exactScheduling, WarmAlarmSupportStatus.unknown);
      expect(caps.notificationScheduling, WarmAlarmSupportStatus.unknown);
      expect(caps.backgroundAudioPlayback, WarmAlarmSupportStatus.unknown);
      expect(caps.fullScreenPresentation, WarmAlarmSupportStatus.unknown);
      expect(caps.wakeCheck, WarmAlarmSupportStatus.unknown);
      expect(caps.liveActivity, WarmAlarmSupportStatus.unknown);
    });

    test('getPermissionState returns stub with all false', () async {
      final state = await methodChannelWarmAlarm.getPermissionState();
      expect(state.notificationsGranted, isFalse);
      expect(state.exactAlarmGranted, isFalse);
      expect(state.fullScreenIntentGranted, isFalse);
    });

    test('getScheduledAlarms returns empty list', () async {
      final alarms = await methodChannelWarmAlarm.getScheduledAlarms();
      expect(alarms, isEmpty);
    });

    test('isRinging returns false', () async {
      expect(await methodChannelWarmAlarm.isRinging(), isFalse);
    });

    test('setKillWarning completes without error', () async {
      await expectLater(
        methodChannelWarmAlarm.setKillWarning(title: 'T', body: 'B'),
        completes,
      );
    });

    test('clearKillWarning completes without error', () async {
      await expectLater(methodChannelWarmAlarm.clearKillWarning(), completes);
    });

    test(
      'scheduleAlarm returns unsupported result without channel traffic',
      () async {
        final result = await methodChannelWarmAlarm.scheduleAlarm(
          WarmAlarmSchedule(
            id: 1,
            scheduledAt: DateTime(2026),
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(),
          ),
        );
        expect(log, isEmpty);
        expect(result.readiness.level, WarmAlarmReadinessLevel.unsupported);
        expect(result.alarmId, 0);
      },
    );
  });
}
