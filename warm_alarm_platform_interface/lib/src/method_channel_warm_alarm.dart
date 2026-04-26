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
  Future<WarmAlarmReadiness> getReadiness() async => _readinessFromMap(
    await methodChannel.invokeMapMethod<String, Object?>('getReadiness'),
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

  WarmAlarmReadiness _readinessFromMap(Map<String, Object?>? map) {
    if (map == null) {
      return const WarmAlarmReadiness(
        level: WarmAlarmReadinessLevel.unsupported,
        reasons: <WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.platformUnsupported,
        ],
      );
    }

    final rawReasons = map['reasons'] as List<Object?>? ?? const <Object?>[];

    return WarmAlarmReadiness(
      level: _readinessLevelFromName(map['level'] as String? ?? 'unsupported'),
      reasons: rawReasons.whereType<String>().map(_readinessReasonFromName).toList(growable: false),
    );
  }

  WarmAlarmReadinessLevel _readinessLevelFromName(String name) {
    switch (name) {
      case 'ready':
        return WarmAlarmReadinessLevel.ready;
      case 'limited':
        return WarmAlarmReadinessLevel.limited;
      case 'blocked':
        return WarmAlarmReadinessLevel.blocked;
      case 'unsupported':
      default:
        return WarmAlarmReadinessLevel.unsupported;
    }
  }

  WarmAlarmReadinessReason _readinessReasonFromName(String name) {
    switch (name) {
      case 'notificationPermissionDenied':
        return WarmAlarmReadinessReason.notificationPermissionDenied;
      case 'exactAlarmPermissionDenied':
        return WarmAlarmReadinessReason.exactAlarmPermissionDenied;
      case 'fullScreenPermissionDenied':
        return WarmAlarmReadinessReason.fullScreenPermissionDenied;
      case 'backgroundExecutionLimited':
        return WarmAlarmReadinessReason.backgroundExecutionLimited;
      case 'backgroundAudioLimited':
        return WarmAlarmReadinessReason.backgroundAudioLimited;
      case 'platformUnsupported':
        return WarmAlarmReadinessReason.platformUnsupported;
      case 'batteryOptimizationMayDelay':
        return WarmAlarmReadinessReason.batteryOptimizationMayDelay;
      case 'unknown':
      default:
        return WarmAlarmReadinessReason.unknown;
    }
  }
}
