import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_android/src/messages.g.dart';
import 'package:warm_alarm_android/warm_alarm_android.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final failed = emitted.single as WarmAlarmFailed;
        expect(failed.alarmId, 5);
        expect(failed.failure.code, WarmAlarmFailureCode.schedulingFailed);
        await sub.cancel();
      },
    );
  });
}
