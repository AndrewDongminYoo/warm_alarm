import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:warm_alarm_android/src/messages.g.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// {@template warm_alarm_android}
/// The Android implementation of [WarmAlarmPlatform].
/// {@endtemplate}
class WarmAlarmAndroid extends WarmAlarmPlatform implements WarmAlarmEventsApi {
  /// {@macro warm_alarm_android}
  WarmAlarmAndroid({
    @visibleForTesting WarmAlarmApi? api,
  }) : api = api ?? WarmAlarmApi();

  /// The API used to interact with the native platform.
  final WarmAlarmApi api;

  final StreamController<WarmAlarmEvent> _events = StreamController<WarmAlarmEvent>.broadcast();

  bool _eventsApiSetUp = false;

  /// Registers this class as the default instance of [WarmAlarmPlatform].
  static void registerWith() {
    WarmAlarmPlatform.instance = WarmAlarmAndroid();
  }

  @override
  Future<void> cancelAlarm(int id) => api.cancelAlarm(id);

  @override
  Future<void> cancelAllAlarms() => api.cancelAllAlarms();

  void _ensureEventsApiSetUp() {
    if (_eventsApiSetUp) return;
    WarmAlarmEventsApi.setUp(this);
    _eventsApiSetUp = true;
  }

  @override
  Stream<WarmAlarmEvent> get events {
    _ensureEventsApiSetUp();
    return _events.stream;
  }

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => _capabilitiesFromWire(await api.getCapabilities());

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async =>
      _permissionStateFromWire(await api.getPermissionState());

  @override
  Future<WarmAlarmReadiness> getReadiness() async => _readinessFromWire(await api.getReadiness());

  @override
  Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async =>
      (await api.getScheduledAlarms()).map(_snapshotFromWire).toList(growable: false);

  @override
  Future<bool> isRinging({int? id}) => api.isRinging(id);

  @override
  Future<void> setKillWarning({required String title, required String body}) => api.setKillWarning(title, body);

  @override
  Future<void> clearKillWarning() => api.clearKillWarning();

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async => _scheduleResultFromWire(
    await api.scheduleAlarm(_scheduleToWire(schedule)),
  );

  @override
  Future<void> emitEvent(WarmAlarmEventWire event) async {
    _events.add(_eventFromWire(event));
  }
}

WarmAlarmAudioWire _audioToWire(WarmAlarmAudio audio) {
  return WarmAlarmAudioWire(
    filePath: audio.filePath,
    assetPath: audio.assetPath,
    loop: audio.loop,
    volume: audio.volume,
    fadeInDurationMillis: audio.fadeInDuration?.inMilliseconds,
    vibrate: audio.vibrate,
    volumeEnforced: audio.volumeEnforced,
    fadeSteps: audio.fadeSteps?.map(_fadeStepToWire).toList(growable: false),
  );
}

WarmAlarmAudio _audioFromWire(WarmAlarmAudioWire wire) {
  return WarmAlarmAudio(
    filePath: wire.filePath,
    assetPath: wire.assetPath,
    loop: wire.loop,
    volume: wire.volume,
    fadeInDuration: wire.fadeInDurationMillis == null ? null : Duration(milliseconds: wire.fadeInDurationMillis!),
    vibrate: wire.vibrate,
    volumeEnforced: wire.volumeEnforced,
    fadeSteps: wire.fadeSteps?.map(_fadeStepFromWire).toList(growable: false),
  );
}

WarmAlarmVolumeFadeStepWire _fadeStepToWire(WarmAlarmVolumeFadeStep step) {
  return WarmAlarmVolumeFadeStepWire(
    timeMillis: step.time.inMilliseconds,
    volume: step.volume,
  );
}

WarmAlarmVolumeFadeStep _fadeStepFromWire(WarmAlarmVolumeFadeStepWire wire) {
  return WarmAlarmVolumeFadeStep(
    time: Duration(milliseconds: wire.timeMillis),
    volume: wire.volume,
  );
}

WarmAlarmCapabilities _capabilitiesFromWire(WarmAlarmCapabilitiesWire wire) {
  return WarmAlarmCapabilities(
    exactScheduling: _supportStatusFromWire(wire.exactScheduling),
    notificationScheduling: _supportStatusFromWire(wire.notificationScheduling),
    backgroundAudioPlayback: _supportStatusFromWire(
      wire.backgroundAudioPlayback,
    ),
    fullScreenPresentation: _supportStatusFromWire(wire.fullScreenPresentation),
    wakeCheck: _supportStatusFromWire(wire.wakeCheck),
    liveActivity: _supportStatusFromWire(wire.liveActivity),
  );
}

WarmAlarmFailure _failureFromWire(WarmAlarmFailureWire wire) {
  return WarmAlarmFailure(
    code: _failureCodeFromWire(wire.code),
    message: wire.message,
  );
}

WarmAlarmFailureCode _failureCodeFromWire(WarmAlarmFailureCodeWire wire) {
  switch (wire) {
    case WarmAlarmFailureCodeWire.unknown:
      return WarmAlarmFailureCode.unknown;
    case WarmAlarmFailureCodeWire.invalidArguments:
      return WarmAlarmFailureCode.invalidArguments;
    case WarmAlarmFailureCodeWire.permissionDenied:
      return WarmAlarmFailureCode.permissionDenied;
    case WarmAlarmFailureCodeWire.exactAlarmUnavailable:
      return WarmAlarmFailureCode.exactAlarmUnavailable;
    case WarmAlarmFailureCodeWire.notificationUnavailable:
      return WarmAlarmFailureCode.notificationUnavailable;
    case WarmAlarmFailureCodeWire.audioFileNotFound:
      return WarmAlarmFailureCode.audioFileNotFound;
    case WarmAlarmFailureCodeWire.audioPlaybackFailed:
      return WarmAlarmFailureCode.audioPlaybackFailed;
    case WarmAlarmFailureCodeWire.schedulingFailed:
      return WarmAlarmFailureCode.schedulingFailed;
    case WarmAlarmFailureCodeWire.platformInternalError:
      return WarmAlarmFailureCode.platformInternalError;
  }
}

WarmAlarmNotificationWire _notificationToWire(
  WarmAlarmNotification notification,
) {
  return WarmAlarmNotificationWire(
    title: notification.title,
    body: notification.body,
    stopActionTitle: notification.stopActionTitle,
    snoozeActionTitle: notification.snoozeActionTitle,
    androidIcon: notification.androidIcon,
    androidIconColor: notification.androidIconColor,
    keepNotificationAfterAlarmEnds: notification.keepNotificationAfterAlarmEnds,
  );
}

WarmAlarmNotification _notificationFromWire(WarmAlarmNotificationWire wire) {
  return WarmAlarmNotification(
    title: wire.title,
    body: wire.body,
    stopActionTitle: wire.stopActionTitle,
    snoozeActionTitle: wire.snoozeActionTitle,
    androidIcon: wire.androidIcon,
    androidIconColor: wire.androidIconColor,
    keepNotificationAfterAlarmEnds: wire.keepNotificationAfterAlarmEnds,
  );
}

WarmAlarmPermissionState _permissionStateFromWire(
  WarmAlarmPermissionStateWire wire,
) {
  return WarmAlarmPermissionState(
    notificationsGranted: wire.notificationsGranted,
    exactAlarmGranted: wire.exactAlarmGranted,
    fullScreenIntentGranted: wire.fullScreenIntentGranted,
  );
}

WarmAlarmReadiness _readinessFromWire(WarmAlarmReadinessWire wire) {
  return WarmAlarmReadiness(
    level: _readinessLevelFromWire(wire.level),
    reasons: wire.reasons.map(_readinessReasonFromWire).toList(growable: false),
  );
}

WarmAlarmReadinessLevel _readinessLevelFromWire(
  WarmAlarmReadinessLevelWire wire,
) {
  switch (wire) {
    case WarmAlarmReadinessLevelWire.ready:
      return WarmAlarmReadinessLevel.ready;
    case WarmAlarmReadinessLevelWire.limited:
      return WarmAlarmReadinessLevel.limited;
    case WarmAlarmReadinessLevelWire.blocked:
      return WarmAlarmReadinessLevel.blocked;
    case WarmAlarmReadinessLevelWire.unsupported:
      return WarmAlarmReadinessLevel.unsupported;
  }
}

WarmAlarmReadinessReason _readinessReasonFromWire(
  WarmAlarmReadinessReasonWire wire,
) {
  switch (wire) {
    case WarmAlarmReadinessReasonWire.notificationPermissionDenied:
      return WarmAlarmReadinessReason.notificationPermissionDenied;
    case WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied:
      return WarmAlarmReadinessReason.exactAlarmPermissionDenied;
    case WarmAlarmReadinessReasonWire.fullScreenPermissionDenied:
      return WarmAlarmReadinessReason.fullScreenPermissionDenied;
    case WarmAlarmReadinessReasonWire.backgroundExecutionLimited:
      return WarmAlarmReadinessReason.backgroundExecutionLimited;
    case WarmAlarmReadinessReasonWire.backgroundAudioLimited:
      return WarmAlarmReadinessReason.backgroundAudioLimited;
    case WarmAlarmReadinessReasonWire.platformUnsupported:
      return WarmAlarmReadinessReason.platformUnsupported;
    case WarmAlarmReadinessReasonWire.batteryOptimizationMayDelay:
      return WarmAlarmReadinessReason.batteryOptimizationMayDelay;
    case WarmAlarmReadinessReasonWire.unknown:
      return WarmAlarmReadinessReason.unknown;
  }
}

WarmAlarmRecurrenceWire? _recurrenceToWire(WarmAlarmRecurrence? recurrence) {
  if (recurrence == null) return null;
  return WarmAlarmRecurrenceWire(weekdays: recurrence.weekdays);
}

WarmAlarmScheduleResult _scheduleResultFromWire(
  WarmAlarmScheduleResultWire wire,
) {
  return WarmAlarmScheduleResult(
    alarmId: wire.alarmId,
    readiness: _readinessFromWire(wire.readiness),
    warning: wire.warning == null ? null : WarmAlarmWarning(message: wire.warning!.message),
  );
}

WarmAlarmScheduleWire _scheduleToWire(WarmAlarmSchedule schedule) {
  return WarmAlarmScheduleWire(
    id: schedule.id,
    scheduledAtMillis: schedule.scheduledAt.millisecondsSinceEpoch,
    notification: _notificationToWire(schedule.notification),
    audio: _audioToWire(schedule.audio),
    recurrence: _recurrenceToWire(schedule.recurrence),
    snooze: _snoozeToWire(schedule.snooze),
    wakeCheck: _wakeCheckToWire(schedule.wakeCheck),
    payload: schedule.payload,
  );
}

WarmAlarmSnapshot _snapshotFromWire(WarmAlarmSnapshotWire wire) {
  return WarmAlarmSnapshot(
    id: wire.id,
    scheduledAt: DateTime.fromMillisecondsSinceEpoch(wire.scheduledAtMillis),
    notification: _notificationFromWire(wire.notification),
    audio: _audioFromWire(wire.audio),
    recurrence: wire.recurrence == null ? null : WarmAlarmRecurrence(weekdays: wire.recurrence!.weekdays),
    snooze: wire.snooze == null
        ? null
        : WarmAlarmSnooze(
            duration: Duration(milliseconds: wire.snooze!.durationMillis),
          ),
    wakeCheck: wire.wakeCheck == null
        ? null
        : WarmAlarmWakeCheck(
            checkDelay: Duration(
              milliseconds: wire.wakeCheck!.checkDelayMillis,
            ),
            retriggerDelay: wire.wakeCheck!.retriggerDelayMillis == null
                ? null
                : Duration(milliseconds: wire.wakeCheck!.retriggerDelayMillis!),
            maxRetriggers: wire.wakeCheck!.maxRetriggers,
          ),
    payload: wire.payload,
  );
}

WarmAlarmSnoozeWire? _snoozeToWire(WarmAlarmSnooze? snooze) {
  if (snooze == null) return null;
  return WarmAlarmSnoozeWire(durationMillis: snooze.duration.inMilliseconds);
}

WarmAlarmSupportStatus _supportStatusFromWire(WarmAlarmSupportStatusWire wire) {
  switch (wire) {
    case WarmAlarmSupportStatusWire.supported:
      return WarmAlarmSupportStatus.supported;
    case WarmAlarmSupportStatusWire.limited:
      return WarmAlarmSupportStatus.limited;
    case WarmAlarmSupportStatusWire.unsupported:
      return WarmAlarmSupportStatus.unsupported;
    case WarmAlarmSupportStatusWire.unknown:
      return WarmAlarmSupportStatus.unknown;
  }
}

WarmAlarmWakeCheckWire? _wakeCheckToWire(WarmAlarmWakeCheck? check) {
  if (check == null) return null;
  return WarmAlarmWakeCheckWire(
    checkDelayMillis: check.checkDelay.inMilliseconds,
    retriggerDelayMillis: check.retriggerDelay?.inMilliseconds,
    maxRetriggers: check.maxRetriggers,
  );
}

int _requireSnoozeDuration(int? millis) {
  assert(
    millis != null,
    'WarmAlarmEventsApi: snoozed event received without snoozeDurationMillis (Kotlin contract violation)',
  );
  return millis ?? 0;
}

WarmAlarmFailureWire _requireFailure(WarmAlarmFailureWire? failure) {
  assert(
    failure != null,
    'WarmAlarmEventsApi: failed event received without failure payload (Kotlin contract violation)',
  );
  return failure ?? WarmAlarmFailureWire(code: WarmAlarmFailureCodeWire.unknown);
}

WarmAlarmEvent _eventFromWire(WarmAlarmEventWire wire) {
  final alarmId = wire.alarmId;
  final occurredAt = DateTime.fromMillisecondsSinceEpoch(wire.occurredAtMillis);
  return switch (wire.type) {
    WarmAlarmEventTypeWire.scheduled => WarmAlarmScheduled(
      alarmId: alarmId,
      occurredAt: occurredAt,
    ),
    WarmAlarmEventTypeWire.fired => WarmAlarmFired(
      alarmId: alarmId,
      occurredAt: occurredAt,
      payload: wire.payload,
    ),
    WarmAlarmEventTypeWire.stopped => WarmAlarmStopped(
      alarmId: alarmId,
      occurredAt: occurredAt,
      payload: wire.payload,
    ),
    WarmAlarmEventTypeWire.snoozed => WarmAlarmSnoozed(
      alarmId: alarmId,
      occurredAt: occurredAt,
      duration: Duration(
        milliseconds: _requireSnoozeDuration(wire.snoozeDurationMillis),
      ),
      payload: wire.payload,
    ),
    WarmAlarmEventTypeWire.failed => WarmAlarmFailed(
      alarmId: alarmId,
      occurredAt: occurredAt,
      failure: _failureFromWire(_requireFailure(wire.failure)),
    ),
    WarmAlarmEventTypeWire.wakeCheckShown => WarmAlarmWakeCheckShown(
      alarmId: alarmId,
      occurredAt: occurredAt,
    ),
    WarmAlarmEventTypeWire.wakeCheckDismissed => WarmAlarmWakeCheckDismissed(
      alarmId: alarmId,
      occurredAt: occurredAt,
    ),
    WarmAlarmEventTypeWire.wakeCheckExpired => WarmAlarmWakeCheckExpired(
      alarmId: alarmId,
      occurredAt: occurredAt,
    ),
    WarmAlarmEventTypeWire.retriggered => WarmAlarmRetriggered(
      alarmId: alarmId,
      occurredAt: occurredAt,
      payload: wire.payload,
    ),
  };
}
