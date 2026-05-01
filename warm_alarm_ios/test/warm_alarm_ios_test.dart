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
          notification: WarmAlarmNotificationWire(title: '', body: ''),
          audio: WarmAlarmAudioWire(loop: true, vibrate: false),
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
            ),
            audio: WarmAlarmAudioWire(loop: false, vibrate: true),
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
}
