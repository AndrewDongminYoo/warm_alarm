import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelWarmAlarm', () {
    late MethodChannelWarmAlarm methodChannelWarmAlarm;
    final log = <MethodCall>[];

    setUp(() {
      methodChannelWarmAlarm = MethodChannelWarmAlarm();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelWarmAlarm.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'getReadiness':
              return <String, Object?>{
                'level': 'unsupported',
                'reasons': <String>['platformUnsupported'],
              };
            default:
              return null;
          }
        },
      );
    });

    tearDown(log.clear);

    test('getReadiness returns a typed unsupported stub without channel traffic', () async {
      final readiness = await methodChannelWarmAlarm.getReadiness();
      expect(log, isEmpty);
      expect(readiness.level, WarmAlarmReadinessLevel.unsupported);
      expect(
        readiness.reasons,
        equals(<WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.platformUnsupported,
        ]),
      );
    });
  });
}
