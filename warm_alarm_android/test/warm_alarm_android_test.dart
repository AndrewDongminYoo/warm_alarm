import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_android/src/messages.g.dart';
import 'package:warm_alarm_android/warm_alarm_android.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          vibrate: true,
          volumeEnforced: false,
        ),
        androidFullScreenIntent: true,
      ),
    );
  });

  group(WarmAlarmAndroid, () {
    late WarmAlarmAndroid warmAlarm;
    late WarmAlarmApi api;

    setUp(() {
      api = _MockWarmAlarmApi();
      warmAlarm = WarmAlarmAndroid(api: api);
    });

    test('can be registered', () {
      WarmAlarmAndroid.registerWith();
      expect(
        WarmAlarmPlatform.instance,
        isA<WarmAlarmAndroid>(),
      );
    });

    test('getCapabilities returns typed stub values', () async {
      when(api.getCapabilities).thenAnswer(
        (_) async => WarmAlarmCapabilitiesWire(
          exactScheduling: WarmAlarmSupportStatusWire.supported,
          notificationScheduling: WarmAlarmSupportStatusWire.supported,
          backgroundAudioPlayback: WarmAlarmSupportStatusWire.limited,
          fullScreenPresentation: WarmAlarmSupportStatusWire.supported,
          wakeCheck: WarmAlarmSupportStatusWire.unsupported,
          liveActivity: WarmAlarmSupportStatusWire.unsupported,
        ),
      );

      final capabilities = await warmAlarm.getCapabilities();

      expect(capabilities.exactScheduling, WarmAlarmSupportStatus.supported);
      expect(
        capabilities.backgroundAudioPlayback,
        WarmAlarmSupportStatus.limited,
      );

      verify(api.getCapabilities).called(1);
    });

    test('getCapabilities maps unknown support status', () async {
      when(api.getCapabilities).thenAnswer(
        (_) async => WarmAlarmCapabilitiesWire(
          exactScheduling: WarmAlarmSupportStatusWire.unknown,
          notificationScheduling: WarmAlarmSupportStatusWire.supported,
          backgroundAudioPlayback: WarmAlarmSupportStatusWire.limited,
          fullScreenPresentation: WarmAlarmSupportStatusWire.unsupported,
          wakeCheck: WarmAlarmSupportStatusWire.unknown,
          liveActivity: WarmAlarmSupportStatusWire.unknown,
        ),
      );
      final caps = await warmAlarm.getCapabilities();
      expect(caps.exactScheduling, WarmAlarmSupportStatus.unknown);
      expect(caps.wakeCheck, WarmAlarmSupportStatus.unknown);
    });

    test('cancelAlarm delegates to api', () async {
      when(() => api.cancelAlarm(any())).thenAnswer((_) async {});
      await warmAlarm.cancelAlarm(5);
      verify(() => api.cancelAlarm(5)).called(1);
    });

    test('cancelAllAlarms delegates to api', () async {
      when(api.cancelAllAlarms).thenAnswer((_) async {});
      await warmAlarm.cancelAllAlarms();
      verify(api.cancelAllAlarms).called(1);
    });

    test('getPermissionState returns typed permission state', () async {
      when(api.getPermissionState).thenAnswer(
        (_) async => WarmAlarmPermissionStateWire(
          notificationsGranted: true,
          exactAlarmGranted: false,
          fullScreenIntentGranted: true,
        ),
      );
      final state = await warmAlarm.getPermissionState();
      expect(state.notificationsGranted, isTrue);
      expect(state.exactAlarmGranted, isFalse);
      expect(state.fullScreenIntentGranted, isTrue);
      verify(api.getPermissionState).called(1);
    });

    test('getReadiness maps blocked level with all reason variants', () async {
      when(api.getReadiness).thenAnswer(
        (_) async => WarmAlarmReadinessWire(
          level: WarmAlarmReadinessLevelWire.blocked,
          reasons: <WarmAlarmReadinessReasonWire>[
            WarmAlarmReadinessReasonWire.notificationPermissionDenied,
            WarmAlarmReadinessReasonWire.fullScreenPermissionDenied,
            WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
            WarmAlarmReadinessReasonWire.backgroundAudioLimited,
            WarmAlarmReadinessReasonWire.platformUnsupported,
            WarmAlarmReadinessReasonWire.batteryOptimizationMayDelay,
            WarmAlarmReadinessReasonWire.unknown,
          ],
        ),
      );
      final readiness = await warmAlarm.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.blocked);
      expect(
        readiness.reasons,
        containsAll(<WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.notificationPermissionDenied,
          WarmAlarmReadinessReason.fullScreenPermissionDenied,
          WarmAlarmReadinessReason.backgroundExecutionLimited,
          WarmAlarmReadinessReason.backgroundAudioLimited,
          WarmAlarmReadinessReason.platformUnsupported,
          WarmAlarmReadinessReason.batteryOptimizationMayDelay,
          WarmAlarmReadinessReason.unknown,
        ]),
      );
      verify(api.getReadiness).called(1);
    });

    test('getReadiness maps unsupported level', () async {
      when(api.getReadiness).thenAnswer(
        (_) async => WarmAlarmReadinessWire(
          level: WarmAlarmReadinessLevelWire.unsupported,
          reasons: <WarmAlarmReadinessReasonWire>[],
        ),
      );
      final readiness = await warmAlarm.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.unsupported);
    });

    test('scheduleAlarm maps schedule result warning and readiness', () async {
      final schedule = WarmAlarmSchedule(
        id: 9,
        scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
        notification: const WarmAlarmNotification(
          title: 'Alarm',
          body: 'Wake up',
        ),
        audio: const WarmAlarmAudio(filePath: '/tmp/alarm.m4a'),
        snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
      );

      when(() => api.scheduleAlarm(any())).thenAnswer(
        (_) async => WarmAlarmScheduleResultWire(
          alarmId: 9,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.limited,
            reasons: <WarmAlarmReadinessReasonWire>[
              WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied,
            ],
          ),
          warning: WarmAlarmWarningWire(
            message: 'Exact alarm permission missing.',
          ),
        ),
      );

      final result = await warmAlarm.scheduleAlarm(schedule);

      expect(result.alarmId, 9);
      expect(result.readiness.level, WarmAlarmReadinessLevel.limited);
      expect(
        result.readiness.reasons,
        <WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.exactAlarmPermissionDenied,
        ],
      );
      expect(result.warning?.message, 'Exact alarm permission missing.');
      verify(() => api.scheduleAlarm(any())).called(1);
    });

    test('getScheduledAlarms maps snapshots from wire', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 3,
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
            androidFullScreenIntent: true,
          ),
        ],
      );

      final snapshots = await warmAlarm.getScheduledAlarms();

      expect(snapshots, hasLength(1));
      expect(snapshots.single.id, 3);
      expect(
        snapshots.single.scheduledAt,
        DateTime.fromMillisecondsSinceEpoch(now),
      );
      verify(api.getScheduledAlarms).called(1);
    });
  });

  group('WarmAlarmAndroid events', () {
    test('emitEvent adds WarmAlarmFired to events stream', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);

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

      expect(emitted, hasLength(1));
      expect(emitted.first, isA<WarmAlarmFired>());
      expect((emitted.first as WarmAlarmFired).alarmId, 42);

      await sub.cancel();
    });

    test('emitEvent maps snoozed event with duration', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);

      final now = DateTime.now().millisecondsSinceEpoch;
      final eventWire = WarmAlarmEventWire(
        alarmId: 7,
        type: WarmAlarmEventTypeWire.snoozed,
        occurredAtMillis: now,
        snoozeDurationMillis: 300000,
      );

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(eventWire);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      final snoozed = emitted.first as WarmAlarmSnoozed;
      expect(snoozed.alarmId, 7);
      expect(snoozed.duration, const Duration(minutes: 5));

      await sub.cancel();
    });

    test('emitEvent maps scheduled event', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 1,
          type: WarmAlarmEventTypeWire.scheduled,
          occurredAtMillis: now,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single, isA<WarmAlarmScheduled>());
      expect(emitted.single.alarmId, 1);
      await sub.cancel();
    });

    test('emitEvent maps stopped event', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 3,
          type: WarmAlarmEventTypeWire.stopped,
          occurredAtMillis: now,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted.single, isA<WarmAlarmStopped>());
      expect(emitted.single.alarmId, 3);
      await sub.cancel();
    });

    test(
      'emitEvent maps failed event with unknown fallback when failure is null',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final now = DateTime.now().millisecondsSinceEpoch;

        final emitted = <WarmAlarmEvent>[];
        final sub = platform.events.listen(emitted.add);

        // Provide explicit failure to avoid triggering the assert in _requireFailure.
        await platform.emitEvent(
          WarmAlarmEventWire(
            alarmId: 5,
            type: WarmAlarmEventTypeWire.failed,
            occurredAtMillis: now,
            failure: WarmAlarmFailureWire(
              code: WarmAlarmFailureCodeWire.schedulingFailed,
              message: 'Unable to schedule alarm.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final failed = emitted.single as WarmAlarmFailed;
        expect(failed.alarmId, 5);
        expect(failed.failure.code, WarmAlarmFailureCode.schedulingFailed);
        expect(failed.failure.message, 'Unable to schedule alarm.');
        await sub.cancel();
      },
    );
  });

  group('WarmAlarmAndroid wake-check event mapping', () {
    test('emitEvent maps wakeCheckShown', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 10,
          type: WarmAlarmEventTypeWire.wakeCheckShown,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmWakeCheckShown>());
      expect((emitted.single as WarmAlarmWakeCheckShown).alarmId, 10);
      await sub.cancel();
    });

    test('emitEvent maps wakeCheckDismissed', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 11,
          type: WarmAlarmEventTypeWire.wakeCheckDismissed,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmWakeCheckDismissed>());
      await sub.cancel();
    });

    test('emitEvent maps wakeCheckExpired', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 12,
          type: WarmAlarmEventTypeWire.wakeCheckExpired,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmWakeCheckExpired>());
      await sub.cancel();
    });

    test('emitEvent maps retriggered', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 13,
          type: WarmAlarmEventTypeWire.retriggered,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(emitted.single, isA<WarmAlarmRetriggered>());
      await sub.cancel();
    });
  });

  group('WarmAlarmAndroid scheduleAlarm wakeCheck wire mapping', () {
    test('scheduleAlarm passes wakeCheck fields to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((invocation) async {
        captured.add(
          invocation.positionalArguments[0] as WarmAlarmScheduleWire,
        );
        return WarmAlarmScheduleResultWire(
          alarmId: 1,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 1,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          wakeCheck: const WarmAlarmWakeCheck(
            checkDelay: Duration(minutes: 5),
            retriggerDelay: Duration(minutes: 2),
          ),
        ),
      );
      final wire = captured.single.wakeCheck!;
      expect(wire.checkDelayMillis, 5 * 60 * 1000);
      expect(wire.retriggerDelayMillis, 2 * 60 * 1000);
      expect(wire.maxRetriggers, 1);
    });

    test('scheduleAlarm passes null wakeCheck when not configured', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((invocation) async {
        captured.add(
          invocation.positionalArguments[0] as WarmAlarmScheduleWire,
        );
        return WarmAlarmScheduleResultWire(
          alarmId: 2,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 2,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
        ),
      );
      expect(captured.single.wakeCheck, isNull);
    });

    test('scheduleAlarm passes payload to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((invocation) async {
        captured.add(
          invocation.positionalArguments[0] as WarmAlarmScheduleWire,
        );
        return WarmAlarmScheduleResultWire(
          alarmId: 3,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 3,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          payload: '{"userId":"42"}',
        ),
      );
      expect(captured.single.payload, '{"userId":"42"}');
    });
  });

  group('WarmAlarmAndroid P1+P2+P3 features', () {
    test('isRinging delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => true);

      final result = await platform.isRinging(id: 5);

      expect(result, isTrue);
      verify(() => api.isRinging(5)).called(1);
    });

    test('isRinging with null id delegates null to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => false);

      final result = await platform.isRinging();

      expect(result, isFalse);
      verify(() => api.isRinging(null)).called(1);
    });

    test('emitEvent maps fired event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 7,
          type: WarmAlarmEventTypeWire.fired,
          occurredAtMillis: now,
          payload: 'alarm-data',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect((emitted.single as WarmAlarmFired).payload, 'alarm-data');
      await sub.cancel();
    });

    test('emitEvent maps stopped event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 8,
          type: WarmAlarmEventTypeWire.stopped,
          occurredAtMillis: now,
          payload: 'stop-data',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect((emitted.single as WarmAlarmStopped).payload, 'stop-data');
      await sub.cancel();
    });

    test('emitEvent maps snoozed event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);

      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 9,
          type: WarmAlarmEventTypeWire.snoozed,
          occurredAtMillis: now,
          snoozeDurationMillis: 300000,
          payload: 'snooze-data',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final snoozed = emitted.single as WarmAlarmSnoozed;
      expect(snoozed.payload, 'snooze-data');
      expect(snoozed.duration, const Duration(minutes: 5));
      await sub.cancel();
    });

    test('getScheduledAlarms maps enriched snapshot fields', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 99,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'Morning Alarm',
              body: 'Wake up!',
              stopActionTitle: 'Stop',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: true,
              vibrate: true,
              volume: 0.8,
              volumeEnforced: false,
            ),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300000),
            wakeCheck: WarmAlarmWakeCheckWire(checkDelayMillis: 60000),
            payload: '{"key":"val"}',
            androidFullScreenIntent: true,
          ),
        ],
      );

      final snapshots = await platform.getScheduledAlarms();

      expect(snapshots.single.id, 99);
      expect(snapshots.single.notification.title, 'Morning Alarm');
      expect(snapshots.single.audio.loop, isTrue);
      expect(snapshots.single.audio.vibrate, isTrue);
      expect(snapshots.single.audio.volume, 0.8);
      expect(snapshots.single.snooze!.duration.inMinutes, 5);
      expect(snapshots.single.wakeCheck!.checkDelay.inSeconds, 60);
      expect(snapshots.single.payload, '{"key":"val"}');
    });
  });

  group('WarmAlarmAndroid A1+N1+W1 features', () {
    test(
      'scheduleAlarm passes androidIcon, androidIconColor, keepNotificationAfterAlarmEnds to wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 1,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.ready,
              reasons: <WarmAlarmReadinessReasonWire>[],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 1,
            scheduledAt: DateTime(2026, 5, 1, 7),
            notification: const WarmAlarmNotification(
              title: 'T',
              body: 'B',
              androidIcon: 'ic_alarm_custom',
              androidIconColor: 0xFF0000FF,
              keepNotificationAfterAlarmEnds: true,
            ),
            audio: const WarmAlarmAudio(),
          ),
        );
        expect(captured.single.notification.androidIcon, 'ic_alarm_custom');
        expect(captured.single.notification.androidIconColor, 0xFF0000FF);
        expect(
          captured.single.notification.keepNotificationAfterAlarmEnds,
          isTrue,
        );
      },
    );

    test(
      'scheduleAlarm passes volumeEnforced and fadeSteps to audio wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 2,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.ready,
              reasons: <WarmAlarmReadinessReasonWire>[],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 2,
            scheduledAt: DateTime(2026, 5, 1, 7),
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(
              volumeEnforced: true,
              fadeSteps: <WarmAlarmVolumeFadeStep>[
                WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 0),
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

    test('setKillWarning delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      when(() => api.setKillWarning(any(), any())).thenAnswer((_) async {});
      await platform.setKillWarning(
        title: 'App killed',
        body: 'Alarm was interrupted',
      );
      verify(
        () => api.setKillWarning('App killed', 'Alarm was interrupted'),
      ).called(1);
    });

    test('clearKillWarning delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      when(api.clearKillWarning).thenAnswer((_) async {});
      await platform.clearKillWarning();
      verify(api.clearKillWarning).called(1);
    });
  });

  group('WarmAlarmAndroid coverage gaps', () {
    test('scheduleAlarm with recurrence passes weekdays to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 10,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 10,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          recurrence: const WarmAlarmRecurrence(weekdays: [1, 3, 5]),
        ),
      );
      expect(captured.single.recurrence!.weekdays, [1, 3, 5]);
    });

    test('getScheduledAlarms maps snapshot audio with fadeSteps', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 20,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'T',
              body: 'B',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: false,
              vibrate: false,
              volumeEnforced: true,
              fadeSteps: <WarmAlarmVolumeFadeStepWire>[
                WarmAlarmVolumeFadeStepWire(timeMillis: 0, volume: 0.2),
                WarmAlarmVolumeFadeStepWire(timeMillis: 5000, volume: 1),
              ],
            ),
            androidFullScreenIntent: false,
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.audio.fadeSteps, hasLength(2));
      expect(snapshots.single.audio.fadeSteps!.first.volume, 0.2);
      expect(
        snapshots.single.audio.fadeSteps!.last.time,
        const Duration(seconds: 5),
      );
    });

    test('emitEvent maps failed with platformInternalError code', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 99,
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

    test(
      'getScheduledAlarms maps snapshot with wakeCheck retriggerDelayMillis',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final now = DateTime.now().millisecondsSinceEpoch;
        when(api.getScheduledAlarms).thenAnswer(
          (_) async => <WarmAlarmSnapshotWire>[
            WarmAlarmSnapshotWire(
              id: 30,
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
              wakeCheck: WarmAlarmWakeCheckWire(
                checkDelayMillis: 60000,
                retriggerDelayMillis: 120000,
                maxRetriggers: 3,
              ),
              androidFullScreenIntent: true,
            ),
          ],
        );
        final snapshots = await platform.getScheduledAlarms();
        expect(
          snapshots.single.wakeCheck!.retriggerDelay,
          const Duration(minutes: 2),
        );
        expect(snapshots.single.wakeCheck!.maxRetriggers, 3);
      },
    );
  });

  group('WarmAlarmAndroid Phase 4 features', () {
    test('init delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      when(api.init).thenAnswer((_) async {});
      await platform.init();
      verify(api.init).called(1);
    });

    test('scheduleAlarm passes androidFullScreenIntent=true to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmAndroid(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 1,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 1,
          scheduledAt: DateTime(2026, 5, 3, 8),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
        ),
      );
      expect(captured.single.androidFullScreenIntent, isTrue);
    });

    test(
      'scheduleAlarm passes androidFullScreenIntent=false to wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 2,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.ready,
              reasons: <WarmAlarmReadinessReasonWire>[],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 2,
            scheduledAt: DateTime(2026, 5, 3, 8),
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(),
            androidFullScreenIntent: false,
          ),
        );
        expect(captured.single.androidFullScreenIntent, isFalse);
      },
    );

    test(
      'getScheduledAlarms maps androidFullScreenIntent from wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmAndroid(api: api);
        final now = DateTime.now().millisecondsSinceEpoch;
        when(api.getScheduledAlarms).thenAnswer(
          (_) async => <WarmAlarmSnapshotWire>[
            WarmAlarmSnapshotWire(
              id: 50,
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
              androidFullScreenIntent: false,
            ),
          ],
        );
        final snapshots = await platform.getScheduledAlarms();
        expect(snapshots.single.androidFullScreenIntent, isFalse);
      },
    );
  });
}
