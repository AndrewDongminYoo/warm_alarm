import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:warm_alarm_ios/src/messages.g.dart';
import 'package:warm_alarm_ios/warm_alarm_ios.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class _Api extends Mock implements WarmAlarmApi {}

void main() {
  setUpAll(
    () => registerFallbackValue(
      WarmAlarmLiveActivityStateWire(
        alarmId: 0,
        title: '',
        status: WarmAlarmLiveActivityStatusWire.scheduled,
      ),
    ),
  );

  test('start maps alarm content and returns the native activity identifier', () async {
    final api = _Api();
    final platform = WarmAlarmIOS(api: api);
    final at = DateTime.fromMillisecondsSinceEpoch(1900000000000);
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

  test('update maps a ringing state without a scheduled time', () async {
    final api = _Api();
    final platform = WarmAlarmIOS(api: api);
    when(() => api.updateLiveActivity(any(), any())).thenAnswer(
      (_) async => WarmAlarmLiveActivityResultWire(
        status: WarmAlarmLiveActivityResultStatusWire.completed,
      ),
    );

    final result = await platform.updateLiveActivity(
      'native-id',
      const WarmAlarmLiveActivityState(
        alarmId: 7,
        title: 'Wake up',
        status: WarmAlarmLiveActivityStatus.ringing,
      ),
    );

    final invocation = verify(() => api.updateLiveActivity(captureAny(), captureAny())).captured;
    expect(invocation[0], 'native-id');
    final state = invocation[1] as WarmAlarmLiveActivityStateWire;
    expect(state.alarmId, 7);
    expect(state.title, 'Wake up');
    expect(state.status, WarmAlarmLiveActivityStatusWire.ringing);
    expect(state.scheduledAtMillis, isNull);
    expect(result.status, WarmAlarmLiveActivityResultStatus.completed);
  });

  test('update maps a scheduled state with its next occurrence', () async {
    final api = _Api();
    final platform = WarmAlarmIOS(api: api);
    final at = DateTime.fromMillisecondsSinceEpoch(1900000000000);
    when(() => api.updateLiveActivity(any(), any())).thenAnswer(
      (_) async => WarmAlarmLiveActivityResultWire(
        status: WarmAlarmLiveActivityResultStatusWire.completed,
      ),
    );

    await platform.updateLiveActivity(
      'native-id',
      WarmAlarmLiveActivityState(
        alarmId: 8,
        title: 'Tomorrow',
        status: WarmAlarmLiveActivityStatus.scheduled,
        scheduledAt: at,
      ),
    );

    final invocation = verify(() => api.updateLiveActivity(captureAny(), captureAny())).captured;
    expect(invocation[0], 'native-id');
    final state = invocation[1] as WarmAlarmLiveActivityStateWire;
    expect(state.status, WarmAlarmLiveActivityStatusWire.scheduled);
    expect(state.scheduledAtMillis, at.millisecondsSinceEpoch);
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
