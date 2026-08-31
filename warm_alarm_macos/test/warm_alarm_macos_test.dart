import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_macos/src/messages.g.dart';
import 'package:warm_alarm_macos/warm_alarm_macos.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmMacOS, () {
    late WarmAlarmMacOS warmAlarm;
    late WarmAlarmApi api;

    setUp(() {
      api = _MockWarmAlarmApi();
      warmAlarm = WarmAlarmMacOS(api: api);
    });

    test('remediation maps every wire status and readiness reason', () async {
      const statuses = <WarmAlarmRemediationStatusWire, WarmAlarmRemediationStatus>{
        WarmAlarmRemediationStatusWire.completed: WarmAlarmRemediationStatus.completed,
        WarmAlarmRemediationStatusWire.unavailable: WarmAlarmRemediationStatus.unavailable,
        WarmAlarmRemediationStatusWire.unsupported: WarmAlarmRemediationStatus.unsupported,
      };
      for (final entry in statuses.entries) {
        when(
          api.requestNotificationPermission,
        ).thenAnswer((_) async => _remediationWire(entry.key));
        expect(
          (await warmAlarm.requestNotificationPermission()).status,
          entry.value,
        );
      }

      const reasons = <WarmAlarmReadinessReason, WarmAlarmReadinessReasonWire>{
        WarmAlarmReadinessReason.notificationPermissionDenied:
            WarmAlarmReadinessReasonWire.notificationPermissionDenied,
        WarmAlarmReadinessReason.exactAlarmPermissionDenied: WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied,
        WarmAlarmReadinessReason.fullScreenPermissionDenied: WarmAlarmReadinessReasonWire.fullScreenPermissionDenied,
        WarmAlarmReadinessReason.backgroundExecutionLimited: WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
        WarmAlarmReadinessReason.backgroundAudioLimited: WarmAlarmReadinessReasonWire.backgroundAudioLimited,
        WarmAlarmReadinessReason.platformUnsupported: WarmAlarmReadinessReasonWire.platformUnsupported,
        WarmAlarmReadinessReason.batteryOptimizationMayDelay: WarmAlarmReadinessReasonWire.batteryOptimizationMayDelay,
        WarmAlarmReadinessReason.unknown: WarmAlarmReadinessReasonWire.unknown,
      };
      for (final entry in reasons.entries) {
        when(() => api.openReadinessSettings(entry.value)).thenAnswer(
          (_) async => _remediationWire(WarmAlarmRemediationStatusWire.completed),
        );
        await warmAlarm.openReadinessSettings(entry.key);
        verify(() => api.openReadinessSettings(entry.value)).called(1);
      }
    });

    test('can be registered', () {
      WarmAlarmMacOS.registerWith();
      expect(
        WarmAlarmPlatform.instance,
        isA<WarmAlarmMacOS>(),
      );
    });

    test('getCapabilities returns typed stub values', () async {
      when(api.getCapabilities).thenAnswer(
        (_) async => WarmAlarmCapabilitiesWire(
          exactScheduling: WarmAlarmSupportStatusWire.unsupported,
          notificationScheduling: WarmAlarmSupportStatusWire.supported,
          backgroundAudioPlayback: WarmAlarmSupportStatusWire.limited,
          fullScreenPresentation: WarmAlarmSupportStatusWire.unsupported,
          wakeCheck: WarmAlarmSupportStatusWire.unsupported,
          liveActivity: WarmAlarmSupportStatusWire.unsupported,
        ),
      );

      final capabilities = await warmAlarm.getCapabilities();

      expect(capabilities.exactScheduling, WarmAlarmSupportStatus.unsupported);
      expect(
        capabilities.notificationScheduling,
        WarmAlarmSupportStatus.supported,
      );

      verify(api.getCapabilities).called(1);
    });
  });

  group('WarmAlarmMacOS events', () {
    test('emitEvent adds WarmAlarmFired to events stream', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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

  group('WarmAlarmMacOS P1+P2+P3 features', () {
    test('isRinging delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => true);

      expect(await platform.isRinging(id: 3), isTrue);
      verify(() => api.isRinging(3)).called(1);
    });

    test('emitEvent maps fired event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 10,
          type: WarmAlarmEventTypeWire.fired,
          occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
          payload: 'macos-payload',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect((emitted.single as WarmAlarmFired).payload, 'macos-payload');
      await sub.cancel();
    });

    test('emitEvent maps stopped event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
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

    test('getScheduledAlarms maps enriched snapshot fields', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;

      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 66,
            scheduledAtMillis: now,
            notification: WarmAlarmNotificationWire(
              title: 'macOS Alarm',
              body: 'Ring',
              keepNotificationAfterAlarmEnds: false,
            ),
            audio: WarmAlarmAudioWire(
              loop: true,
              vibrate: false,
              volume: 0.5,
              volumeEnforced: false,
            ),
            snooze: WarmAlarmSnoozeWire(durationMillis: 600000),
            payload: 'mac-payload',
          ),
        ],
      );

      final snapshots = await platform.getScheduledAlarms();

      expect(snapshots.single.id, 66);
      expect(snapshots.single.notification.title, 'macOS Alarm');
      expect(snapshots.single.audio.volume, 0.5);
      expect(snapshots.single.snooze!.duration.inMinutes, 10);
      expect(snapshots.single.payload, 'mac-payload');
      expect(snapshots.single.wakeCheck, isNull);
    });
  });

  group('WarmAlarmMacOS A1+N1+W1 features', () {
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
        final platform = WarmAlarmMacOS(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 40,
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
            id: 40,
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
      when(api.clearKillWarning).thenAnswer((_) async {});
      await platform.clearKillWarning();
      verify(api.clearKillWarning).called(1);
    });
  });

  group('WarmAlarmMacOS API delegation', () {
    test('cancelAlarm delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(() => api.cancelAlarm(any())).thenAnswer((_) async {});
      await platform.cancelAlarm(5);
      verify(() => api.cancelAlarm(5)).called(1);
    });

    test('cancelAllAlarms delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(api.cancelAllAlarms).thenAnswer((_) async {});
      await platform.cancelAllAlarms();
      verify(api.cancelAllAlarms).called(1);
    });

    test('getPermissionState returns typed state', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(api.getPermissionState).thenAnswer(
        (_) async => WarmAlarmPermissionStateWire(
          notificationsGranted: true,
          exactAlarmGranted: false,
          fullScreenIntentGranted: false,
        ),
      );
      final state = await platform.getPermissionState();
      expect(state.notificationsGranted, isTrue);
      expect(state.exactAlarmGranted, isFalse);
    });

    test('requestNotificationPermission maps the native remediation result', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(api.requestNotificationPermission).thenAnswer(
        (_) async => WarmAlarmRemediationResultWire(
          status: WarmAlarmRemediationStatusWire.completed,
          permissionState: WarmAlarmPermissionStateWire(
            notificationsGranted: true,
            exactAlarmGranted: false,
            fullScreenIntentGranted: false,
          ),
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.limited,
            reasons: <WarmAlarmReadinessReasonWire>[
              WarmAlarmReadinessReasonWire.backgroundExecutionLimited,
            ],
          ),
        ),
      );

      final result = await platform.requestNotificationPermission();

      expect(result.status, WarmAlarmRemediationStatus.completed);
      expect(result.permissionState.notificationsGranted, isTrue);
    });

    test('openReadinessSettings maps an unsupported macOS result', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(
        () => api.openReadinessSettings(
          WarmAlarmReadinessReasonWire.notificationPermissionDenied,
        ),
      ).thenAnswer(
        (_) async => WarmAlarmRemediationResultWire(
          status: WarmAlarmRemediationStatusWire.unsupported,
          permissionState: WarmAlarmPermissionStateWire(
            notificationsGranted: false,
            exactAlarmGranted: false,
            fullScreenIntentGranted: false,
          ),
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.unsupported,
            reasons: <WarmAlarmReadinessReasonWire>[
              WarmAlarmReadinessReasonWire.platformUnsupported,
            ],
          ),
        ),
      );

      final result = await platform.openReadinessSettings(
        WarmAlarmReadinessReason.notificationPermissionDenied,
      );

      expect(result.status, WarmAlarmRemediationStatus.unsupported);
      verify(
        () => api.openReadinessSettings(
          WarmAlarmReadinessReasonWire.notificationPermissionDenied,
        ),
      ).called(1);
    });

    test('getReadiness maps ready level', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
      when(() => api.isRinging(any())).thenAnswer((_) async => false);
      final result = await platform.isRinging();
      expect(result, isFalse);
      verify(() => api.isRinging(null)).called(1);
    });

    test('emitEvent maps snoozed event with payload', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
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
      final platform = WarmAlarmMacOS(api: api);
      final emitted = <WarmAlarmEvent>[];
      final sub = platform.events.listen(emitted.add);
      await platform.emitEvent(
        WarmAlarmEventWire(
          alarmId: 77,
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

  group('WarmAlarmMacOS schedule and snapshot wire mapping', () {
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

    test('scheduleAlarm passes payload to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 70,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 70,
          scheduledAt: DateTime(2026, 5, 1, 8),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          payload: 'mac-sched-payload',
        ),
      );
      expect(captured.single.payload, 'mac-sched-payload');
    });

    test('scheduleAlarm with recurrence passes weekdays to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 71,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 71,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(),
          recurrence: const WarmAlarmRecurrence(weekdays: [2, 4, 6]),
        ),
      );
      expect(captured.single.recurrence!.weekdays, [2, 4, 6]);
    });

    test('scheduleAlarm with snooze passes duration to wire', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 72,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 72,
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
      final platform = WarmAlarmMacOS(api: api);
      final captured = <WarmAlarmScheduleWire>[];
      when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
        captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
        return WarmAlarmScheduleResultWire(
          alarmId: 73,
          readiness: WarmAlarmReadinessWire(
            level: WarmAlarmReadinessLevelWire.ready,
            reasons: <WarmAlarmReadinessReasonWire>[],
          ),
        );
      });
      await platform.scheduleAlarm(
        WarmAlarmSchedule(
          id: 73,
          scheduledAt: DateTime(2026, 5, 1, 7),
          notification: const WarmAlarmNotification(title: 'T', body: 'B'),
          audio: const WarmAlarmAudio(fadeInDuration: Duration(seconds: 20)),
        ),
      );
      expect(captured.single.audio.fadeInDurationMillis, 20000);
    });

    test('getScheduledAlarms maps snapshot with recurrence', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 80,
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
            recurrence: WarmAlarmRecurrenceWire(weekdays: [1, 7]),
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.recurrence!.weekdays, [1, 7]);
    });

    test('getScheduledAlarms maps snapshot audio with fadeSteps', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      final now = DateTime.now().millisecondsSinceEpoch;
      when(api.getScheduledAlarms).thenAnswer(
        (_) async => <WarmAlarmSnapshotWire>[
          WarmAlarmSnapshotWire(
            id: 81,
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
                WarmAlarmVolumeFadeStepWire(timeMillis: 0, volume: 0.4),
                WarmAlarmVolumeFadeStepWire(timeMillis: 8000, volume: 1),
              ],
            ),
          ),
        ],
      );
      final snapshots = await platform.getScheduledAlarms();
      expect(snapshots.single.audio.fadeSteps, hasLength(2));
      expect(snapshots.single.audio.fadeSteps!.first.volume, 0.4);
    });

    test(
      'getScheduledAlarms maps snapshot audio with fadeInDuration',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmMacOS(api: api);
        final now = DateTime.now().millisecondsSinceEpoch;
        when(api.getScheduledAlarms).thenAnswer(
          (_) async => <WarmAlarmSnapshotWire>[
            WarmAlarmSnapshotWire(
              id: 82,
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
                fadeInDurationMillis: 12000,
              ),
            ),
          ],
        );
        final snapshots = await platform.getScheduledAlarms();
        expect(
          snapshots.single.audio.fadeInDuration,
          const Duration(seconds: 12),
        );
      },
    );

    test(
      'scheduleAlarm with fadeSteps in audio passes to wire',
      () async {
        final api = _MockWarmAlarmApi();
        final platform = WarmAlarmMacOS(api: api);
        final captured = <WarmAlarmScheduleWire>[];
        when(() => api.scheduleAlarm(any())).thenAnswer((inv) async {
          captured.add(inv.positionalArguments[0] as WarmAlarmScheduleWire);
          return WarmAlarmScheduleResultWire(
            alarmId: 74,
            readiness: WarmAlarmReadinessWire(
              level: WarmAlarmReadinessLevelWire.ready,
              reasons: <WarmAlarmReadinessReasonWire>[],
            ),
          );
        });
        await platform.scheduleAlarm(
          WarmAlarmSchedule(
            id: 74,
            scheduledAt: DateTime(2026, 5, 1, 7),
            notification: const WarmAlarmNotification(title: 'T', body: 'B'),
            audio: const WarmAlarmAudio(
              volumeEnforced: true,
              fadeSteps: <WarmAlarmVolumeFadeStep>[
                WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 0.1),
                WarmAlarmVolumeFadeStep(
                  time: Duration(seconds: 15),
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

  group('WarmAlarmMacOS Phase 4 features', () {
    test('init delegates to api', () async {
      final api = _MockWarmAlarmApi();
      final platform = WarmAlarmMacOS(api: api);
      when(api.initialize).thenAnswer((_) async {});
      await platform.init();
      verify(api.initialize).called(1);
    });
  });
}

WarmAlarmRemediationResultWire _remediationWire(
  WarmAlarmRemediationStatusWire status,
) => WarmAlarmRemediationResultWire(
  status: status,
  permissionState: WarmAlarmPermissionStateWire(
    notificationsGranted: true,
    exactAlarmGranted: true,
    fullScreenIntentGranted: true,
  ),
  readiness: WarmAlarmReadinessWire(
    level: WarmAlarmReadinessLevelWire.ready,
    reasons: <WarmAlarmReadinessReasonWire>[],
  ),
);
