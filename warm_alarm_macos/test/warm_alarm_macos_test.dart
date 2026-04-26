import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_macos/src/messages.g.dart';
import 'package:warm_alarm_macos/warm_alarm_macos.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmMacOS, () {
    const kPlatformName = 'MacOS';
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

    test('getPlatformName returns correct name', () async {
      when(api.getPlatformName).thenAnswer((_) async => kPlatformName);

      await expectLater(
        warmAlarm.getPlatformName(),
        completion(equals(kPlatformName)),
      );

      verify(api.getPlatformName).called(1);
    });
  });
}
