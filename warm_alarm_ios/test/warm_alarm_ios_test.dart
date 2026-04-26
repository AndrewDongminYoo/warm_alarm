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

      expect(capabilities.notificationScheduling, WarmAlarmSupportStatus.supported);
      expect(capabilities.liveActivity, WarmAlarmSupportStatus.supported);

      verify(api.getCapabilities).called(1);
    });
  });
}
