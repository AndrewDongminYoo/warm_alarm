import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'warm_alarm',
    swiftOut: 'ios/warm_alarm_ios/Sources/warm_alarm_ios/Messages.g.swift',
    swiftOptions: SwiftOptions(),
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

enum WarmAlarmNotificationAuthorizationStatusWire {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}

enum WarmAlarmRemediationStatusWire {
  completed,
  unavailable,
  unsupported,
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

class WarmAlarmNotificationSettingsWire {
  const WarmAlarmNotificationSettingsWire({
    required this.authorizationStatus,
    required this.alertsEnabled,
    required this.soundsEnabled,
    required this.timeSensitiveEnabled,
  });

  final WarmAlarmNotificationAuthorizationStatusWire authorizationStatus;
  final bool alertsEnabled;
  final bool soundsEnabled;
  final bool? timeSensitiveEnabled;
}

class WarmAlarmReadinessWire {
  const WarmAlarmReadinessWire({
    required this.level,
    required this.reasons,
    this.notificationSettings,
  });

  final WarmAlarmReadinessLevelWire level;
  final List<WarmAlarmReadinessReasonWire> reasons;
  final WarmAlarmNotificationSettingsWire? notificationSettings;
}

class WarmAlarmRemediationResultWire {
  const WarmAlarmRemediationResultWire({
    required this.status,
    required this.permissionState,
    required this.readiness,
  });

  final WarmAlarmRemediationStatusWire status;
  final WarmAlarmPermissionStateWire permissionState;
  final WarmAlarmReadinessWire readiness;
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
    this.systemSoundFilePath,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final int? fadeInDurationMillis;
  final bool vibrate;
  final bool volumeEnforced;
  final List<WarmAlarmVolumeFadeStepWire>? fadeSteps;
  final String? systemSoundFilePath;
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
    this.payload,
  });

  final int id;
  final int scheduledAtMillis;
  final WarmAlarmNotificationWire notification;
  final WarmAlarmAudioWire audio;
  final WarmAlarmRecurrenceWire? recurrence;
  final WarmAlarmSnoozeWire? snooze;
  final String? payload;
}

class WarmAlarmSnapshotWire {
  const WarmAlarmSnapshotWire({
    required this.id,
    required this.scheduledAtMillis,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
    this.payload,
    this.systemManagedAudio,
  });

  final int id;
  final int scheduledAtMillis;
  final WarmAlarmNotificationWire notification;
  final WarmAlarmAudioWire audio;
  final WarmAlarmRecurrenceWire? recurrence;
  final WarmAlarmSnoozeWire? snooze;
  final String? payload;
  final bool? systemManagedAudio;
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

enum WarmAlarmLiveActivityStatusWire { scheduled, ringing, snoozed }

enum WarmAlarmLiveActivityResultStatusWire { completed, unsupported, disabled, notFound }

class WarmAlarmLiveActivityStateWire {
  const WarmAlarmLiveActivityStateWire({
    required this.alarmId,
    required this.title,
    required this.status,
    this.scheduledAtMillis,
  });

  final int alarmId;
  final String title;
  final WarmAlarmLiveActivityStatusWire status;
  final int? scheduledAtMillis;
}

class WarmAlarmLiveActivityResultWire {
  const WarmAlarmLiveActivityResultWire({required this.status, this.activityId});

  final WarmAlarmLiveActivityResultStatusWire status;
  final String? activityId;
}

@HostApi()
abstract class WarmAlarmApi {
  @asyncCallback
  void initialize();

  @asyncCallback
  WarmAlarmCapabilitiesWire getCapabilities();

  @asyncCallback
  WarmAlarmPermissionStateWire getPermissionState();

  @asyncCallback
  WarmAlarmReadinessWire getReadiness();

  @asyncCallback
  WarmAlarmRemediationResultWire requestNotificationPermission();

  @asyncCallback
  WarmAlarmRemediationResultWire openReadinessSettings(WarmAlarmReadinessReasonWire reason);

  @asyncCallback
  WarmAlarmScheduleResultWire scheduleAlarm(WarmAlarmScheduleWire schedule);

  @asyncCallback
  String? prepareSystemSound(String primaryFilePath, String? backgroundAssetPath);

  @asyncCallback
  void cancelAlarm(int id);

  @asyncCallback
  void cancelAllAlarms();

  @asyncCallback
  List<WarmAlarmSnapshotWire> getScheduledAlarms();

  @asyncCallback
  bool isRinging(int? alarmId);

  @asyncCallback
  void setKillWarning(String title, String body);

  @asyncCallback
  void clearKillWarning();

  @asyncCallback
  WarmAlarmLiveActivityResultWire startLiveActivity(WarmAlarmLiveActivityStateWire state);

  @asyncCallback
  WarmAlarmLiveActivityResultWire updateLiveActivity(String activityId, WarmAlarmLiveActivityStateWire state);

  @asyncCallback
  WarmAlarmLiveActivityResultWire endLiveActivity(String activityId);
}

@FlutterApi()
abstract class WarmAlarmEventsApi {
  @asyncCallback
  void emitEvent(WarmAlarmEventWire event);
}
