import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kPlatformName = 'platformName';

  group('$MethodChannelWarmAlarm', () {
    late MethodChannelWarmAlarm
    methodChannelWarmAlarm;
    final log = <MethodCall>[];

    setUp(() {
      methodChannelWarmAlarm = MethodChannelWarmAlarm();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            methodChannelWarmAlarm.methodChannel,
            (methodCall) async {
              log.add(methodCall);
              switch (methodCall.method) {
                case 'getPlatformName':
                  return kPlatformName;
                default:
                  return null;
              }
            },
          );
    });

    tearDown(log.clear);

    test('getPlatformName', () async {
      final platformName = await methodChannelWarmAlarm
          .getPlatformName();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformName', arguments: null)],
      );
      expect(platformName, equals(kPlatformName));
    });
  });
}
