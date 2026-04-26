import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'warm_alarm',
    kotlinOut: 'android/src/main/kotlin/com/andrew/alarm/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.andrew.alarm'),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
enum WarmAlarmSupportStatusWire {
  supported,
  limited,
  unsupported,
  unknown,
}

enum WarmAlarmReadinessLevelWire {
  ready,
  limited,
  blocked,
  unsupported,
}

enum WarmAlarmReadinessReasonWire {
  notificationPermissionDenied,
  exactAlarmPermissionDenied,
  fullScreenPermissionDenied,
  backgroundExecutionLimited,
  backgroundAudioLimited,
  platformUnsupported,
  batteryOptimizationMayDelay,
  unknown,
}

enum WarmAlarmFailureCodeWire {
  unknown,
  invalidArguments,
  permissionDenied,
  exactAlarmUnavailable,
  notificationUnavailable,
  audioFileNotFound,
  audioPlaybackFailed,
  schedulingFailed,
  platformInternalError,
}

enum WarmAlarmEventTypeWire {
  scheduled,
  fired,
  stopped,
  snoozed,
  failed,
}

class WarmAlarmCapabilitiesWire {
  const WarmAlarmCapabilitiesWire({
    required this.exactScheduling,
    required this.notificationScheduling,
    required this.backgroundAudioPlayback,
    required this.fullScreenPresentation,
    required this.wakeCheck,
    required this.liveActivity,
  });

  final WarmAlarmSupportStatusWire exactScheduling;
  final WarmAlarmSupportStatusWire notificationScheduling;
  final WarmAlarmSupportStatusWire backgroundAudioPlayback;
  final WarmAlarmSupportStatusWire fullScreenPresentation;
  final WarmAlarmSupportStatusWire wakeCheck;
  final WarmAlarmSupportStatusWire liveActivity;
}

class WarmAlarmPermissionStateWire {
  const WarmAlarmPermissionStateWire({
    required this.notificationsGranted,
    required this.exactAlarmGranted,
    required this.fullScreenIntentGranted,
  });

  final bool notificationsGranted;
  final bool exactAlarmGranted;
  final bool fullScreenIntentGranted;
}

class WarmAlarmReadinessWire {
  const WarmAlarmReadinessWire({
    required this.level,
    required this.reasons,
  });

  final WarmAlarmReadinessLevelWire level;
  final List<WarmAlarmReadinessReasonWire> reasons;
}

class WarmAlarmWarningWire {
  const WarmAlarmWarningWire({
    required this.message,
  });

  final String message;
}

class WarmAlarmFailureWire {
  const WarmAlarmFailureWire({
    required this.code,
    this.message,
  });

  final WarmAlarmFailureCodeWire code;
  final String? message;
}

class WarmAlarmScheduleResultWire {
  const WarmAlarmScheduleResultWire({
    required this.alarmId,
    required this.readiness,
    this.warning,
  });

  final int alarmId;
  final WarmAlarmReadinessWire readiness;
  final WarmAlarmWarningWire? warning;
}

class WarmAlarmNotificationWire {
  const WarmAlarmNotificationWire({
    required this.title,
    required this.body,
    this.stopActionTitle,
    this.snoozeActionTitle,
  });

  final String title;
  final String body;
  final String? stopActionTitle;
  final String? snoozeActionTitle;
}

class WarmAlarmAudioWire {
  const WarmAlarmAudioWire({
    required this.loop,
    required this.vibrate,
    this.filePath,
    this.assetPath,
    this.volume,
    this.fadeInDurationMillis,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final int? fadeInDurationMillis;
  final bool vibrate;
}

class WarmAlarmRecurrenceWire {
  const WarmAlarmRecurrenceWire({
    required this.weekdays,
  });

  final List<int> weekdays;
}

class WarmAlarmSnoozeWire {
  const WarmAlarmSnoozeWire({
    required this.durationMillis,
  });

  final int durationMillis;
}

class WarmAlarmScheduleWire {
  const WarmAlarmScheduleWire({
    required this.id,
    required this.scheduledAtMillis,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
  });

  final int id;
  final int scheduledAtMillis;
  final WarmAlarmNotificationWire notification;
  final WarmAlarmAudioWire audio;
  final WarmAlarmRecurrenceWire? recurrence;
  final WarmAlarmSnoozeWire? snooze;
}

class WarmAlarmSnapshotWire {
  const WarmAlarmSnapshotWire({
    required this.id,
    required this.scheduledAtMillis,
  });

  final int id;
  final int scheduledAtMillis;
}

class WarmAlarmEventWire {
  const WarmAlarmEventWire({
    required this.alarmId,
    required this.type,
    required this.occurredAtMillis,
    this.snoozeDurationMillis,
    this.failure,
  });

  final int alarmId;
  final WarmAlarmEventTypeWire type;
  final int occurredAtMillis;
  final int? snoozeDurationMillis;
  final WarmAlarmFailureWire? failure;
}

@HostApi()
abstract class WarmAlarmApi {
  @async
  WarmAlarmCapabilitiesWire getCapabilities();

  @async
  WarmAlarmPermissionStateWire getPermissionState();

  @async
  WarmAlarmReadinessWire getReadiness();

  @async
  WarmAlarmScheduleResultWire scheduleAlarm(WarmAlarmScheduleWire schedule);

  @async
  void cancelAlarm(int id);

  @async
  void cancelAllAlarms();

  @async
  List<WarmAlarmSnapshotWire> getScheduledAlarms();
}

@FlutterApi()
abstract class WarmAlarmEventsApi {
  @async
  void emitEvent(WarmAlarmEventWire event);
}
