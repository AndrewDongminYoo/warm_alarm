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
}
