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
      expect(capabilities.notificationScheduling, WarmAlarmSupportStatus.supported);

      verify(api.getCapabilities).called(1);
    });
  });
}
