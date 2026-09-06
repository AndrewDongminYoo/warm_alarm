import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_ios/warm_alarm_ios.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _CustomWidgetsFlutterBinding extends WidgetsFlutterBinding {}

void main() {
  test('registerWith leaves Flutter binding initialization to the app', () async {
    expect(WarmAlarmIOS.registerWith, returnsNormally);
    expect(WarmAlarmPlatform.instance, isA<WarmAlarmIOS>());
    expect(_CustomWidgetsFlutterBinding.new, returnsNormally);
    await Future<void>.delayed(Duration.zero);
  });
}
