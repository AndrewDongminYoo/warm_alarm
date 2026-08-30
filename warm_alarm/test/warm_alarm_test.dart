import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm/warm_alarm.dart';

class MockWarmAlarmPlatform extends Mock with MockPlatformInterfaceMixin implements WarmAlarmPlatform {}

WarmAlarmSchedule _schedule({
  WarmAlarmAudio audio = const WarmAlarmAudio(),
  WarmAlarmRecurrence? recurrence,
  WarmAlarmSnooze? snooze,
  WarmAlarmWakeCheck? wakeCheck,
}) => WarmAlarmSchedule(
  id: 1,
  scheduledAt: DateTime(2026, 4, 27, 7),
  notification: const WarmAlarmNotification(title: 'Wake up', body: 'Now'),
  audio: audio,
  recurrence: recurrence,
  snooze: snooze,
  wakeCheck: wakeCheck,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(_schedule()));

  group(WarmAlarm, () {
    late WarmAlarmPlatform warmAlarmPlatform;

    setUp(() {
      warmAlarmPlatform = MockWarmAlarmPlatform();
      WarmAlarmPlatform.instance = warmAlarmPlatform;
    });

    test(
      'scheduleAlarm accepts zero values and forwards the typed result',
      () async {
        final schedule = _schedule(
          audio: const WarmAlarmAudio(
            volume: 0,
            fadeInDuration: Duration.zero,
            fadeSteps: <WarmAlarmVolumeFadeStep>[
              WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 0),
            ],
          ),
          recurrence: const WarmAlarmRecurrence(
            weekdays: <int>[DateTime.monday],
          ),
          snooze: const WarmAlarmSnooze(duration: Duration.zero),
          wakeCheck: const WarmAlarmWakeCheck(
            checkDelay: Duration.zero,
            retriggerDelay: Duration.zero,
            maxRetriggers: 0,
          ),
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

    final invalidSchedules =
        <
          ({
            String argumentName,
            String description,
            WarmAlarmSchedule schedule,
          })
        >[
          (
            argumentName: 'schedule.recurrence.weekdays',
            description: 'an empty recurring weekday list',
            schedule: _schedule(
              recurrence: const WarmAlarmRecurrence(weekdays: <int>[]),
            ),
          ),
          (
            argumentName: 'schedule.recurrence.weekdays',
            description: 'a recurring weekday outside the ISO range',
            schedule: _schedule(
              recurrence: const WarmAlarmRecurrence(weekdays: <int>[8]),
            ),
          ),
          (
            argumentName: 'schedule.snooze.duration',
            description: 'a negative snooze duration',
            schedule: _schedule(
              snooze: const WarmAlarmSnooze(duration: Duration(seconds: -1)),
            ),
          ),
          (
            argumentName: 'schedule.audio.volume',
            description: 'audio volume above one',
            schedule: _schedule(audio: const WarmAlarmAudio(volume: 1.1)),
          ),
          (
            argumentName: 'schedule.audio.volume',
            description: 'audio volume below zero',
            schedule: _schedule(audio: const WarmAlarmAudio(volume: -0.1)),
          ),
          (
            argumentName: 'schedule.audio.volume',
            description: 'a non-finite audio volume',
            schedule: _schedule(
              audio: const WarmAlarmAudio(volume: double.nan),
            ),
          ),
          (
            argumentName: 'schedule.audio.fadeSteps.time',
            description: 'a negative fade step time',
            schedule: _schedule(
              audio: const WarmAlarmAudio(
                fadeSteps: <WarmAlarmVolumeFadeStep>[
                  WarmAlarmVolumeFadeStep(
                    time: Duration(seconds: -1),
                    volume: 0.5,
                  ),
                ],
              ),
            ),
          ),
          (
            argumentName: 'schedule.audio.fadeSteps.volume',
            description: 'fade step volume above one',
            schedule: _schedule(
              audio: const WarmAlarmAudio(
                fadeSteps: <WarmAlarmVolumeFadeStep>[
                  WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 1.1),
                ],
              ),
            ),
          ),
          (
            argumentName: 'schedule.audio.fadeSteps.volume',
            description: 'fade step volume below zero',
            schedule: _schedule(
              audio: const WarmAlarmAudio(
                fadeSteps: <WarmAlarmVolumeFadeStep>[
                  WarmAlarmVolumeFadeStep(time: Duration.zero, volume: -0.1),
                ],
              ),
            ),
          ),
          (
            argumentName: 'schedule.audio.fadeSteps.volume',
            description: 'a non-finite fade step volume',
            schedule: _schedule(
              audio: const WarmAlarmAudio(
                fadeSteps: <WarmAlarmVolumeFadeStep>[
                  WarmAlarmVolumeFadeStep(
                    time: Duration.zero,
                    volume: double.nan,
                  ),
                ],
              ),
            ),
          ),
          (
            argumentName: 'schedule.audio.fadeInDuration',
            description: 'a negative fade-in duration',
            schedule: _schedule(
              audio: const WarmAlarmAudio(
                fadeInDuration: Duration(seconds: -1),
              ),
            ),
          ),
          (
            argumentName: 'schedule.wakeCheck.checkDelay',
            description: 'a negative wake check delay',
            schedule: _schedule(
              wakeCheck: const WarmAlarmWakeCheck(
                checkDelay: Duration(seconds: -1),
              ),
            ),
          ),
          (
            argumentName: 'schedule.wakeCheck.retriggerDelay',
            description: 'a negative wake check retrigger delay',
            schedule: _schedule(
              wakeCheck: const WarmAlarmWakeCheck(
                checkDelay: Duration.zero,
                retriggerDelay: Duration(seconds: -1),
              ),
            ),
          ),
          (
            argumentName: 'schedule.wakeCheck.maxRetriggers',
            description: 'a negative wake check retrigger count',
            schedule: _schedule(
              wakeCheck: const WarmAlarmWakeCheck(
                checkDelay: Duration.zero,
                maxRetriggers: -1,
              ),
            ),
          ),
        ];

    for (final testCase in invalidSchedules) {
      test('scheduleAlarm rejects ${testCase.description}', () async {
        await expectLater(
          WarmAlarm.scheduleAlarm(testCase.schedule),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              testCase.argumentName,
            ),
          ),
        );
        verifyNever(() => warmAlarmPlatform.scheduleAlarm(any()));
      });
    }

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
