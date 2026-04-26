import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarmMock extends WarmAlarmPlatform {
  static const mockPlatformName = 'Mock';

  @override
  Future<String?> getPlatformName() async => mockPlatformName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('WarmAlarmPlatformInterface', () {
    late WarmAlarmPlatform warmAlarmPlatform;

    setUp(() {
      warmAlarmPlatform = WarmAlarmMock();
      WarmAlarmPlatform.instance = warmAlarmPlatform;
    });

    group('getPlatformName', () {
      test('returns correct name', () async {
        expect(
          await WarmAlarmPlatform.instance.getPlatformName(),
          equals(WarmAlarmMock.mockPlatformName),
        );
      });
    });
  });
}
