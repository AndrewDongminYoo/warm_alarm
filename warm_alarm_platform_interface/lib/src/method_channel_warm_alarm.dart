import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// An implementation of [WarmAlarmPlatform]
/// that uses method channels.
class MethodChannelWarmAlarm extends WarmAlarmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('warm_alarm');

  @override
  Future<void> cancelAlarm(int id) async {}

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Stream<WarmAlarmEvent> get events => const Stream<WarmAlarmEvent>.empty();

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => const WarmAlarmCapabilities(
    exactScheduling: WarmAlarmSupportStatus.unknown,
    notificationScheduling: WarmAlarmSupportStatus.unknown,
    backgroundAudioPlayback: WarmAlarmSupportStatus.unknown,
    fullScreenPresentation: WarmAlarmSupportStatus.unknown,
    wakeCheck: WarmAlarmSupportStatus.unknown,
    liveActivity: WarmAlarmSupportStatus.unknown,
  );

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async => const WarmAlarmPermissionState(
    notificationsGranted: false,
    exactAlarmGranted: false,
    fullScreenIntentGranted: false,
  );

  @override
  Future<WarmAlarmReadiness> getReadiness() async => const WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.unsupported,
    reasons: <WarmAlarmReadinessReason>[
      WarmAlarmReadinessReason.platformUnsupported,
    ],
  );

  @override
  Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async => const <WarmAlarmSnapshot>[];

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async => const WarmAlarmScheduleResult(
    alarmId: 0,
    readiness: WarmAlarmReadiness(
      level: WarmAlarmReadinessLevel.unsupported,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.platformUnsupported,
      ],
    ),
  );
}
