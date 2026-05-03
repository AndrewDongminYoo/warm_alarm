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
  wakeCheckShown,
  wakeCheckDismissed,
  wakeCheckExpired,
  retriggered,
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
    required this.keepNotificationAfterAlarmEnds,
    this.stopActionTitle,
    this.snoozeActionTitle,
    this.androidIcon,
    this.androidIconColor,
  });

  final String title;
  final String body;
  final String? stopActionTitle;
  final String? snoozeActionTitle;
  final String? androidIcon;
  final int? androidIconColor;
  final bool keepNotificationAfterAlarmEnds;
}

class WarmAlarmVolumeFadeStepWire {
  const WarmAlarmVolumeFadeStepWire({
    required this.timeMillis,
    required this.volume,
  });

  final int timeMillis;
  final double volume;
}

class WarmAlarmAudioWire {
  const WarmAlarmAudioWire({
    required this.loop,
    required this.vibrate,
    required this.volumeEnforced,
    this.filePath,
    this.assetPath,
    this.volume,
    this.fadeInDurationMillis,
    this.fadeSteps,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final int? fadeInDurationMillis;
  final bool vibrate;
  final bool volumeEnforced;
  final List<WarmAlarmVolumeFadeStepWire>? fadeSteps;
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

class WarmAlarmWakeCheckWire {
  const WarmAlarmWakeCheckWire({
    required this.checkDelayMillis,
    this.retriggerDelayMillis,
    this.maxRetriggers,
  });

  final int checkDelayMillis;
  final int? retriggerDelayMillis;
  final int? maxRetriggers;
}

class WarmAlarmScheduleWire {
  const WarmAlarmScheduleWire({
    required this.id,
    required this.scheduledAtMillis,
    required this.notification,
    required this.audio,
    required this.androidFullScreenIntent,
    this.recurrence,
    this.snooze,
    this.wakeCheck,
    this.payload,
  });

  final int id;
  final int scheduledAtMillis;
  final WarmAlarmNotificationWire notification;
  final WarmAlarmAudioWire audio;
  final WarmAlarmRecurrenceWire? recurrence;
  final WarmAlarmSnoozeWire? snooze;
  final WarmAlarmWakeCheckWire? wakeCheck;
  final String? payload;
  final bool androidFullScreenIntent;
}

class WarmAlarmSnapshotWire {
  const WarmAlarmSnapshotWire({
    required this.id,
    required this.scheduledAtMillis,
    required this.notification,
    required this.audio,
    required this.androidFullScreenIntent,
    this.recurrence,
    this.snooze,
    this.wakeCheck,
    this.payload,
  });

  final int id;
  final int scheduledAtMillis;
  final WarmAlarmNotificationWire notification;
  final WarmAlarmAudioWire audio;
  final WarmAlarmRecurrenceWire? recurrence;
  final WarmAlarmSnoozeWire? snooze;
  final WarmAlarmWakeCheckWire? wakeCheck;
  final String? payload;
  final bool androidFullScreenIntent;
}

class WarmAlarmEventWire {
  const WarmAlarmEventWire({
    required this.alarmId,
    required this.type,
    required this.occurredAtMillis,
    this.snoozeDurationMillis,
    this.failure,
    this.payload,
  });

  final int alarmId;
  final WarmAlarmEventTypeWire type;
  final int occurredAtMillis;
  final int? snoozeDurationMillis;
  final WarmAlarmFailureWire? failure;
  final String? payload;
}

@HostApi()
abstract class WarmAlarmApi {
  @async
  void initialize();

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

  @async
  bool isRinging(int? alarmId);

  @async
  void setKillWarning(String title, String body);

  @async
  void clearKillWarning();
}

@FlutterApi()
abstract class WarmAlarmEventsApi {
  @async
  void emitEvent(WarmAlarmEventWire event);
}
