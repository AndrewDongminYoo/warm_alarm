import 'dart:async';

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

    test(
      'scheduleAlarm forwards to platform and returns typed result',
      () async {
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
      },
    );

    test('getCapabilities delegates to platform', () async {
      when(warmAlarmPlatform.getCapabilities).thenAnswer(
        (_) async => const WarmAlarmCapabilities(
          exactScheduling: WarmAlarmSupportStatus.supported,
          notificationScheduling: WarmAlarmSupportStatus.supported,
          backgroundAudioPlayback: WarmAlarmSupportStatus.supported,
          fullScreenPresentation: WarmAlarmSupportStatus.supported,
          wakeCheck: WarmAlarmSupportStatus.supported,
          liveActivity: WarmAlarmSupportStatus.unsupported,
        ),
      );
      final caps = await WarmAlarm.getCapabilities();
      expect(caps.exactScheduling, WarmAlarmSupportStatus.supported);
      verify(warmAlarmPlatform.getCapabilities).called(1);
    });

    test('getPermissionState delegates to platform', () async {
      when(warmAlarmPlatform.getPermissionState).thenAnswer(
        (_) async => const WarmAlarmPermissionState(
          notificationsGranted: true,
          exactAlarmGranted: true,
          fullScreenIntentGranted: false,
        ),
      );
      final state = await WarmAlarm.getPermissionState();
      expect(state.notificationsGranted, isTrue);
      verify(warmAlarmPlatform.getPermissionState).called(1);
    });

    test('getReadiness delegates to platform', () async {
      when(warmAlarmPlatform.getReadiness).thenAnswer(
        (_) async => const WarmAlarmReadiness(
          level: WarmAlarmReadinessLevel.ready,
          reasons: <WarmAlarmReadinessReason>[],
        ),
      );
      final readiness = await WarmAlarm.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.ready);
      verify(warmAlarmPlatform.getReadiness).called(1);
    });

    test('cancelAlarm delegates to platform', () async {
      when(() => warmAlarmPlatform.cancelAlarm(any())).thenAnswer((_) async {});
      await WarmAlarm.cancelAlarm(3);
      verify(() => warmAlarmPlatform.cancelAlarm(3)).called(1);
    });

    test('cancelAllAlarms delegates to platform', () async {
      when(warmAlarmPlatform.cancelAllAlarms).thenAnswer((_) async {});
      await WarmAlarm.cancelAllAlarms();
      verify(warmAlarmPlatform.cancelAllAlarms).called(1);
    });

    test('getScheduledAlarms delegates to platform', () async {
      when(
        warmAlarmPlatform.getScheduledAlarms,
      ).thenAnswer((_) async => const <WarmAlarmSnapshot>[]);
      final alarms = await WarmAlarm.getScheduledAlarms();
      expect(alarms, isEmpty);
      verify(warmAlarmPlatform.getScheduledAlarms).called(1);
    });

    test('events delegates to platform stream', () {
      when(() => warmAlarmPlatform.events).thenAnswer(
        (_) => const Stream<WarmAlarmEvent>.empty(),
      );
      expect(WarmAlarm.events, isA<Stream<WarmAlarmEvent>>());
      verify(() => warmAlarmPlatform.events).called(1);
    });

    test('isRinging delegates to platform', () async {
      when(() => warmAlarmPlatform.isRinging(id: any(named: 'id'))).thenAnswer(
        (_) async => false,
      );
      final result = await WarmAlarm.isRinging();
      expect(result, isFalse);
      verify(() => warmAlarmPlatform.isRinging()).called(1);
    });

    test('setKillWarning delegates to platform', () async {
      when(
        () => warmAlarmPlatform.setKillWarning(
          title: any(named: 'title'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async {});
      await WarmAlarm.setKillWarning(
        title: 'App killed',
        body: 'Alarm stopped',
      );
      verify(
        () => warmAlarmPlatform.setKillWarning(
          title: 'App killed',
          body: 'Alarm stopped',
        ),
      ).called(1);
    });

    test('clearKillWarning delegates to platform', () async {
      when(warmAlarmPlatform.clearKillWarning).thenAnswer((_) async {});
      await WarmAlarm.clearKillWarning();
      verify(warmAlarmPlatform.clearKillWarning).called(1);
    });

    test('init delegates to platform', () async {
      when(warmAlarmPlatform.init).thenAnswer((_) async {});
      await WarmAlarm.init();
      verify(warmAlarmPlatform.init).called(1);
    });

    test('hasAlarm returns true when future alarms exist', () async {
      final future = DateTime.now().add(const Duration(hours: 1));
      when(warmAlarmPlatform.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshot>[
          WarmAlarmSnapshot(
            id: 1,
            scheduledAt: future,
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(),
          ),
        ],
      );
      expect(await WarmAlarm.hasAlarm(), isTrue);
    });

    test('hasAlarm returns false when no alarms exist', () async {
      when(
        warmAlarmPlatform.getScheduledAlarms,
      ).thenAnswer((_) async => const <WarmAlarmSnapshot>[]);
      expect(await WarmAlarm.hasAlarm(), isFalse);
    });

    test(
      'hasAlarm returns false when only expired alarms remain in store',
      () async {
        final past = DateTime.now().subtract(const Duration(hours: 1));
        when(warmAlarmPlatform.getScheduledAlarms).thenAnswer(
          (_) async => <WarmAlarmSnapshot>[
            WarmAlarmSnapshot(
              id: 1,
              scheduledAt: past,
              notification: const WarmAlarmNotification(title: 'T', body: 'B'),
              audio: const WarmAlarmAudio(),
            ),
          ],
        );
        expect(await WarmAlarm.hasAlarm(), isFalse);
      },
    );

    test('getAlarm returns matching future snapshot', () async {
      final future = DateTime.now().add(const Duration(hours: 1));
      final snap = WarmAlarmSnapshot(
        id: 42,
        scheduledAt: future,
        notification: const WarmAlarmNotification(title: 'T', body: 'B'),
        audio: const WarmAlarmAudio(),
      );
      when(warmAlarmPlatform.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshot>[snap],
      );
      expect(await WarmAlarm.getAlarm(42), snap);
    });

    test('getAlarm returns null when id not found', () async {
      when(
        warmAlarmPlatform.getScheduledAlarms,
      ).thenAnswer((_) async => const <WarmAlarmSnapshot>[]);
      expect(await WarmAlarm.getAlarm(99), isNull);
    });

    test('getAlarm returns null when matching alarm is expired', () async {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      when(warmAlarmPlatform.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshot>[
          WarmAlarmSnapshot(
            id: 42,
            scheduledAt: past,
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(),
          ),
        ],
      );
      expect(await WarmAlarm.getAlarm(42), isNull);
    });
  });
}
