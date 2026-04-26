import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_ios/src/messages.g.dart';
import 'package:warm_alarm_ios/warm_alarm_ios.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock
    implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmIOS, () {
    const kPlatformName = 'iOS';
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
