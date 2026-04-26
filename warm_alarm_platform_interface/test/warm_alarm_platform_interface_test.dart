import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarmMock extends WarmAlarmPlatform {
  final _events = StreamController<WarmAlarmEvent>.broadcast();

  @override
  Future<void> cancelAlarm(int id) async {}

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Stream<WarmAlarmEvent> get events => _events.stream;

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => const WarmAlarmCapabilities(
    exactScheduling: WarmAlarmSupportStatus.supported,
    notificationScheduling: WarmAlarmSupportStatus.supported,
    backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
    fullScreenPresentation: WarmAlarmSupportStatus.unsupported,
    wakeCheck: WarmAlarmSupportStatus.unsupported,
    liveActivity: WarmAlarmSupportStatus.unsupported,
  );

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async => const WarmAlarmPermissionState(
    notificationsGranted: true,
    exactAlarmGranted: false,
    fullScreenIntentGranted: false,
  );

  @override
  Future<WarmAlarmReadiness> getReadiness() async => const WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.limited,
    reasons: <WarmAlarmReadinessReason>[
      WarmAlarmReadinessReason.exactAlarmPermissionDenied,
    ],
  );

  @override
  Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async => const <WarmAlarmSnapshot>[];

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async => const WarmAlarmScheduleResult(
    alarmId: 7,
    readiness: WarmAlarmReadiness(
      level: WarmAlarmReadinessLevel.limited,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WarmAlarmPlatform exposes typed scheduling APIs', () async {
    final platform = WarmAlarmMock();
    WarmAlarmPlatform.instance = platform;

    expect(
      await WarmAlarmPlatform.instance.getCapabilities(),
      isA<WarmAlarmCapabilities>(),
    );
    expect(
      await WarmAlarmPlatform.instance.getPermissionState(),
      isA<WarmAlarmPermissionState>(),
    );
    expect(
      await WarmAlarmPlatform.instance.getReadiness(),
      isA<WarmAlarmReadiness>(),
    );
  });
}
