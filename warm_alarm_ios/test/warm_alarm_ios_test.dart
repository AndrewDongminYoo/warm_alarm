import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_ios/src/messages.g.dart';
import 'package:warm_alarm_ios/warm_alarm_ios.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmIOS, () {
    late WarmAlarmIOS warmAlarm;
    late WarmAlarmApi api;

    setUp(() {
      api = _MockWarmAlarmApi();
      warmAlarm = WarmAlarmIOS(api: api);
    });

    test('can be registered', () {
      WarmAlarmIOS.registerWith();
      expect(
        WarmAlarmPlatform.instance,
        isA<WarmAlarmIOS>(),
      );
    });

    test('getCapabilities returns typed stub values', () async {
      when(api.getCapabilities).thenAnswer(
        (_) async => WarmAlarmCapabilitiesWire(
          exactScheduling: WarmAlarmSupportStatusWire.limited,
          notificationScheduling: WarmAlarmSupportStatusWire.supported,
          backgroundAudioPlayback: WarmAlarmSupportStatusWire.limited,
          fullScreenPresentation: WarmAlarmSupportStatusWire.unsupported,
          wakeCheck: WarmAlarmSupportStatusWire.unsupported,
          liveActivity: WarmAlarmSupportStatusWire.supported,
        ),
      );

      final capabilities = await warmAlarm.getCapabilities();

      expect(
        capabilities.notificationScheduling,
        WarmAlarmSupportStatus.supported,
      );
      expect(capabilities.liveActivity, WarmAlarmSupportStatus.supported);

      verify(api.getCapabilities).called(1);
    });
  });

  group('WarmAlarmIOS events', () {
    test('emitEvent adds WarmAlarmFired to events stream', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      final eventWire = WarmAlarmEventWire(
        alarmId: 42,
        type: WarmAlarmEventTypeWire.fired,
        occurredAtMillis: now,
      );
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(eventWire);
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmFired>());
      expect((emitted.single as WarmAlarmFired).alarmId, 42);
      await sub.cancel();
    });

    test('emitEvent maps snoozed event with duration', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final eventWire = WarmAlarmEventWire(
        alarmId: 7,
        type: WarmAlarmEventTypeWire.snoozed,
        occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        snoozeDurationMillis: 300000,
      );
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(eventWire);
      await Future<void>.delayed(Duration.zero);
      expect(
        (emitted.single as WarmAlarmSnoozed).duration,
        const Duration(minutes: 5),
      );
      await sub.cancel();
    });

    test('emitEvent maps scheduled event', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 1,
          type: WarmAlarmEventTypeWire.scheduled,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmScheduled>());
      await sub.cancel();
    });

    test('emitEvent maps stopped event', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 3,
          type: WarmAlarmEventTypeWire.stopped,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmStopped>());
      await sub.cancel();
    });

    test('emitEvent maps failed event with provided failure', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 5,
          type: WarmAlarmEventTypeWire.failed,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          failure: WarmAlarmFailureWire(
            code: WarmAlarmFailureCodeWire.schedulingFailed,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (emitted.single as WarmAlarmFailed).failure.code,
        WarmAlarmFailureCode.schedulingFailed,
      );
      await sub.cancel();
    });
  });

  group('WarmAlarmIOS P1+P2+P3 features', () {
    setUpAll(() {
      registerFallbackValue(
        WarmAlarmScheduleWire(
          id: 0,
          scheduledAtMillis: 0,
          notification: WarmAlarmNotificationWire(
            title: '',
            body: '',
            keepNotificationAfterAlarmEnds: false,
          ),
          audio: WarmAlarmAudioWire(
            loop: true,
            vibrate: false,
            volumeEnforced: false,
          ),
        ),
      );
    });

    test('isRinging delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => true);

      expect(await platform.isRinging(id: 3), isTrue);
      verify(() => api.isRinging(3)).called(1);
    });

    test('emitEvent maps fired event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 10,
          type: WarmAlarmEventTypeWire.fired,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          payload: 'ios-payload',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect((emitted.single as WarmAlarmFired).payload, 'ios-payload');
      await sub.cancel();
    });

    test('emitEvent maps stopped event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 11,
          type: WarmAlarmEventTypeWire.stopped,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          payload: 'stop-payload',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect((emitted.single as WarmAlarmStopped).payload, 'stop-payload');
      await sub.cancel();
    });

    test('scheduleAlarm passes payload to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 20,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.limited,
            reasons: <WarmAlarmReadinessReasonWire>[
              WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
            ],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 20,
          scheduledAt: DateTime(2026, 5, 1, 8),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          payload: 'ios-sched-payload',
        ),
      );
      expect(captured.single.payload, 'ios-sched-payload');
    });

    test('getScheduledAlarms maps enriched snapshot fields', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 55,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'iOS Alarm',
              body: 'Ring',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: false,
              vibrate: true,
              volumeEnforced: false,
            ),
            payload: 'snap-payload',
          ),
        ],
      );

      final snapshots = await platform.getScheduledAlarms();

      expect(snapshots.single.id, 55);
      expect(snapshots.single.notification.title, 'iOS Alarm');
      expect(snapshots.single.audio.vibrate, isTrue);
      expect(snapshots.single.payload, 'snap-payload');
      expect(snapshots.single.wakeCheck, isNull);
    });
  });

  group('WarmAlarmIOS A1+N1+W1 features', () {
    setUpAll(() {
      registerFallbackValue(
        WarmAlarmScheduleWire(
          id: 0,
          scheduledAtMillis: 0,
          notification: WarmAlarmNotificationWire(
            title: '',
            body: '',
            keepNotificationAfterAlarmEnds: false,
          ),
          audio: WarmAlarmAudioWire(
            loop: true,
            vibrate: false,
            volumeEnforced: false,
          ),
        ),
      );
    });

    test(
      'scheduleAlarm passes keepNotificationAfterAlarmEnds, androidIcon, volumeEnforced to wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmIOS(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 30,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.limited,
              reasons: <WarmAlarmReadinessReasonWire>[
                WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
              ],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 30,
            scheduledAt: DateTime(2026, 5, 1, 8),
            notification: const WarmAlarmNotification(
              title: 'T',
              body: 'B',
              androidIcon: 'ic_alarm_custom',
              keepNotificationAfterAlarmEnds: true,
            ),
            audio: const WarmAlarmAudio(volumeEnforced: true),
          ),
        );
        expect(
          captured.single.notification.keepNotificationAfterAlarmEnds,
          isTrue,
        );
        expect(captured.single.notification.androidIcon, 'ic_alarm_custom');
        expect(captured.single.audio.volumeEnforced, isTrue);
      },
    );

    test('setKillWarning delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(() => api.setKillWarning(any(), any())).thenAnswer((_) async {});
      await platform.setKillWarning(
        title: 'App killed',
        body: 'Alarm interrupted',
      );
      verify(
        () => api.setKillWarning('App killed', 'Alarm interrupted'),
      ).called(1);
    });

    test('clearKillWarning delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.clearKillWarning).thenAnswer((_) async {});
      await platform.clearKillWarning();
      verify(api.clearKillWarning).called(1);
    });
  });

  group('WarmAlarmIOS API delegation', () {
    test('cancelAlarm delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(() => api.cancelAlarm(any())).thenAnswer((_) async {});
      await platform.cancelAlarm(5);
      verify(() => api.cancelAlarm(5)).called(1);
    });

    test('cancelAllAlarms delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.cancelAllAlarms).thenAnswer((_) async {});
      await platform.cancelAllAlarms();
      verify(api.cancelAllAlarms).called(1);
    });

    test('getPermissionState returns typed state', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.getPermissionState).thenAnswer(
        (_) async => WarmAlarmPermissionStateWire(
          notificationsGranted: true,
          exactAlarmGranted: false,
          fullScreenIntentGranted: true,
        ),
      );
      final state = await platform.getPermissionState();
      expect(state.notificationsGranted, isTrue);
      expect(state.exactAlarmGranted, isFalse);
      expect(state.fullScreenIntentGranted, isTrue);
    });

    test('getReadiness maps ready level', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.getReadiness).thenAnswer(
        (_) async => WarmAlarmReadinessWire(
          level: WarmAlarmReadinessLevelWire.ready,
          reasons: <WarmAlarmReadinessReasonWire>[],
        ),
      );
      final readiness = await platform.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.ready);
    });

    test('getReadiness maps blocked level with all reasons', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.getReadiness).thenAnswer(
        (_) async => WarmAlarmReadinessWire(
          level: WarmAlarmReadinessLevelWire.blocked,
          reasons: <WarmAlarmReadinessReasonWire>[
            WarmAlarmReadinessReasonWire.notificationPermissionDenied,
            WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied,
            WarmAlarmReadinessReasonWire.fullScreenPermissionDenied,
            WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
            WarmAlarmReadinessReasonWire.backgroundAudioLimited,
            WarmAlarmReadinessReasonWire.platformUnsupported,
            WarmAlarmReadinessReasonWire.batteryOptimizationMayDelay,
            WarmAlarmReadinessReasonWire.unknown,
          ],
        ),
      );
      final readiness = await platform.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.blocked);
      expect(
        readiness.reasons,
        containsAll(<WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.notificationPermissionDenied,
          WarmAlarmReadinessReason.exactAlarmPermissionDenied,
          WarmAlarmReadinessReason.fullScreenPermissionDenied,
          WarmAlarmReadinessReason.backgroundExecutionLimited,
          WarmAlarmReadinessReason.backgroundAudioLimited,
          WarmAlarmReadinessReason.platformUnsupported,
          WarmAlarmReadinessReason.batteryOptimizationMayDelay,
          WarmAlarmReadinessReason.unknown,
        ]),
      );
    });

    test('getReadiness maps unsupported level', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.getReadiness).thenAnswer(
        (_) async => WarmAlarmReadinessWire(
          level: WarmAlarmReadinessLevelWire.unsupported,
          reasons: <WarmAlarmReadinessReasonWire>[],
        ),
      );
      final readiness = await platform.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.unsupported);
    });

    test('getCapabilities maps unknown support status', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(api.getCapabilities).thenAnswer(
        (_) async => WarmAlarmCapabilitiesWire(
          exactScheduling: WarmAlarmSupportStatusWire.unknown,
          notificationScheduling: WarmAlarmSupportStatusWire.unknown,
          backgroundAudioPlayback: WarmAlarmSupportStatusWire.unknown,
          fullScreenPresentation: WarmAlarmSupportStatusWire.unknown,
          wakeCheck: WarmAlarmSupportStatusWire.unknown,
          liveActivity: WarmAlarmSupportStatusWire.unknown,
        ),
      );
      final caps = await platform.getCapabilities();
      expect(caps.exactScheduling, WarmAlarmSupportStatus.unknown);
      expect(caps.liveActivity, WarmAlarmSupportStatus.unknown);
    });

    test('isRinging with null id delegates null', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => false);
      final result = await platform.isRinging();
      expect(result, isFalse);
      verify(() => api.isRinging(null)).called(1);
    });

    test('emitEvent maps snoozed event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 20,
          type: WarmAlarmEventTypeWire.snoozed,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          snoozeDurationMillis: 600000,
          payload: 'snooze-payload',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final snoozed = emitted.single as WarmAlarmSnoozed;
      expect(snoozed.duration, const Duration(minutes: 10));
      expect(snoozed.payload, 'snooze-payload');
      await sub.cancel();
    });

    test('emitEvent maps failed with platformInternalError code', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 88,
          type: WarmAlarmEventTypeWire.failed,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          failure: WarmAlarmFailureWire(
            code: WarmAlarmFailureCodeWire.platformInternalError,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (emitted.single as WarmAlarmFailed).failure.code,
        WarmAlarmFailureCode.platformInternalError,
      );
      await sub.cancel();
    });
  });

  group('WarmAlarmIOS schedule and snapshot wire mapping', () {
    setUpAll(() {
      registerFallbackValue(
        WarmAlarmScheduleWire(
          id: 0,
          scheduledAtMillis: 0,
          notification: WarmAlarmNotificationWire(
            title: '',
            body: '',
            keepNotificationAfterAlarmEnds: false,
          ),
          audio: WarmAlarmAudioWire(
            loop: true,
            vibrate: false,
            volumeEnforced: false,
          ),
        ),
      );
    });

    test('scheduleAlarm with recurrence passes weekdays to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 50,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 50,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          recurrence: const WarmAlarmRecurrence(weekdays: [1, 3, 5]),
        ),
      );
      expect(captured.single.recurrence!.weekdays, [1, 3, 5]);
    });

    test('scheduleAlarm with snooze passes duration to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 51,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 51,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          snooze: const WarmAlarmSnooze(duration: Duration(minutes: 10)),
        ),
      );
      expect(captured.single.snooze!.durationMillis, 10 * 60 * 1000);
    });

    test('scheduleAlarm with fadeInDuration passes to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 52,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 52,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(
            fadeInDuration: Duration(seconds: 30),
          ),
        ),
      );
      expect(captured.single.audio.fadeInDurationMillis, 30000);
    });

    test('getScheduledAlarms maps snapshot with recurrence', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 60,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'T',
              body: 'B',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: false,
              vibrate: false,
              volumeEnforced: false,
            ),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [2, 4]),
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.recurrence!.weekdays, [2, 4]);
    });

    test('getScheduledAlarms maps snapshot with snooze', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 61,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'T',
              body: 'B',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: false,
              vibrate: false,
              volumeEnforced: false,
            ),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300000),
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.snooze!.duration.inMinutes, 5);
    });

    test('getScheduledAlarms maps snapshot audio with fadeSteps', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmIOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 62,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'T',
              body: 'B',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: false,
              vibrate: false,
              volumeEnforced: false,
              fadeSteps: <WarmAlarmVolumeFadeStepWire>[
                WarmAlarmVolumeFadeStepWire(timeMillis: 0, volume: 0.3),
                WarmAlarmVolumeFadeStepWire(timeMillis: 10000, volume: 1),
              ],
            ),
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.audio.fadeSteps, hasLength(2));
      expect(snapshots.single.audio.fadeSteps!.first.volume, 0.3);
    });

    test(
      'getScheduledAlarms maps snapshot audio with fadeInDuration',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmIOS(api: api);
        final now = DateTime.now().millisecondsSinceEpoch;
        when(api.getScheduledAlarms).thenAnswer(
          (_) async => <WarmAlarmSnapshotWire>[
            WarmAlarmSnapshotWire(
              id: 63,
              scheduledAtMillis: now,
              notification: WarmAlarmNotificationWire(
                title: 'T',
                body: 'B',
                keepNotificationAfterAlarmEnds: false,
              ),
              audio: WarmAlarmAudioWire(
                loop: false,
                vibrate: false,
                volumeEnforced: false,
                fadeInDurationMillis: 15000,
              ),
            ),
          ],
        );
        final snapshots = await platform.getScheduledAlarms();
        expect(
          snapshots.single.audio.fadeInDuration,
          const Duration(seconds: 15),
        );
      },
    );

    test(
      'scheduleAlarm with fadeSteps in audio passes to wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmIOS(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 53,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.ready,
              reasons: <WarmAlarmReadinessReasonWire>[],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 53,
            scheduledAt: DateTime(2026, 5, 1, 7),
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(
              volumeEnforced: true,
              fadeSteps: <WarmAlarmVolumeFadeStep>[
                WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 0.2),
                WarmAlarmVolumeFadeStep(
                  time: Duration(seconds: 10),
                  volume: 1,
                ),
              ],
            ),
          ),
        );
        expect(captured.single.audio.volumeEnforced, isTrue);
        expect(captured.single.audio.fadeSteps, hasLength(2));
        expect(captured.single.audio.fadeSteps!.first.timeMillis, 0);
        expect(captured.single.audio.fadeSteps!.last.volume, 1.0);
      },
    );
  });
}
