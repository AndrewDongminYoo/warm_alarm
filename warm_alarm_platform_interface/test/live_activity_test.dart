import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

import 'warm_alarm_platform_interface_test.dart' show WarmAlarmMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in <WarmAlarmPlatform>[WarmAlarmMock(), MethodChannelWarmAlarm()]) {
    test('${platform.runtimeType} reports unsupported without a native integration', () async {
      const state = WarmAlarmLiveActivityState(
        alarmId: 7,
        title: 'Morning alarm',
        status: WarmAlarmLiveActivityStatus.ringing,
      );
      final results = <WarmAlarmLiveActivityResult>[
        await platform.startLiveActivity(state),
        await platform.updateLiveActivity('missing', state),
        await platform.endLiveActivity('missing'),
      ];
      for (final result in results) {
        expect(result.status, WarmAlarmLiveActivityResultStatus.unsupported);
        expect(result.activityId, isNull);
      }
    });
  }
}
