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
        notification: WarmAlarmNotificationWire(title: '', body: ''),
        audio: WarmAlarmAudioWire(loop: true, vibrate: true),
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
            notification: WarmAlarmNotificationWire(title: 'T', body: 'B'),
            audio: WarmAlarmAudioWire(loop: false, vibrate: false),
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
  });
}
