import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_android/src/messages.g.dart';
import 'package:warm_alarm_android/warm_alarm_android.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _MockWarmAlarmApi extends Mock
    implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmAndroid, () {
    const kPlatformName = 'Android';
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
