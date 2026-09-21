import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_ios/src/messages.g.dart';
import 'package:warm_alarm_ios/warm_alarm_ios.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _Api extends Mock implements WarmAlarmApi {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start maps alarm content and returns the native activity identifier', () async {
    final api = _Api();
    final platform = WarmAlarmIOS(api: api);
    final at = DateTime.fromMillisecondsSinceEpoch(1900000000000);
    registerFallbackValue(
      WarmAlarmLiveActivityStateWire(
        alarmId: 0,
        title: '',
        status: WarmAlarmLiveActivityStatusWire.scheduled,
      ),
    );
    when(() => api.startLiveActivity(any())).thenAnswer(
      (_) async => WarmAlarmLiveActivityResultWire(
        status: WarmAlarmLiveActivityResultStatusWire.completed,
        activityId: 'native-id',
      ),
    );

    final result = await platform.startLiveActivity(
      WarmAlarmLiveActivityState(
        alarmId: 42,
        title: 'Morning alarm',
        status: WarmAlarmLiveActivityStatus.snoozed,
        scheduledAt: at,
      ),
    );

    final state = verify(() => api.startLiveActivity(captureAny())).captured.single as WarmAlarmLiveActivityStateWire;
    expect(state.alarmId, 42);
    expect(state.title, 'Morning alarm');
    expect(state.status, WarmAlarmLiveActivityStatusWire.snoozed);
    expect(state.scheduledAtMillis, 1900000000000);
    expect(result.status, WarmAlarmLiveActivityResultStatus.completed);
    expect(result.activityId, 'native-id');
  });

  test('end preserves every native outcome', () async {
    final api = _Api();
    final platform = WarmAlarmIOS(api: api);
    const outcomes = <WarmAlarmLiveActivityResultStatusWire, WarmAlarmLiveActivityResultStatus>{
      WarmAlarmLiveActivityResultStatusWire.completed: WarmAlarmLiveActivityResultStatus.completed,
      WarmAlarmLiveActivityResultStatusWire.unsupported: WarmAlarmLiveActivityResultStatus.unsupported,
      WarmAlarmLiveActivityResultStatusWire.disabled: WarmAlarmLiveActivityResultStatus.disabled,
      WarmAlarmLiveActivityResultStatusWire.notFound: WarmAlarmLiveActivityResultStatus.notFound,
    };
    for (final entry in outcomes.entries) {
      when(() => api.endLiveActivity('native-id')).thenAnswer(
        (_) async => WarmAlarmLiveActivityResultWire(status: entry.key),
      );
      expect((await platform.endLiveActivity('native-id')).status, entry.value);
    }
  });
}
