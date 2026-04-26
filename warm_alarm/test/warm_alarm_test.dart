import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class MockWarmAlarmPlatform extends Mock with MockPlatformInterfaceMixin implements WarmAlarmPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(WarmAlarmPlatform, () {
    late WarmAlarmPlatform warmAlarmPlatform;

    setUp(() {
      warmAlarmPlatform = MockWarmAlarmPlatform();
      WarmAlarmPlatform.instance = warmAlarmPlatform;
    });

    group('getPlatformName', () {
      test(
        'returns correct name when platform implementation exists',
        () async {
          const platformName = '__test_platform__';
          when(
            () => warmAlarmPlatform.getPlatformName(),
          ).thenAnswer((_) async => platformName);

          final actualPlatformName = await getPlatformName();
          expect(actualPlatformName, equals(platformName));
        },
      );

      test(
        'throws exception when platform implementation is missing',
        () async {
          when(
            () => warmAlarmPlatform.getPlatformName(),
          ).thenAnswer((_) async => null);

          expect(getPlatformName, throwsException);
        },
      );
    });
  });
}
