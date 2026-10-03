import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

export 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// Schedules alarms and exposes the current platform's capabilities and readiness.
/// Inspect platform limits and scheduling warnings instead of assuming identical behavior across platforms.
class WarmAlarm {
  static WarmAlarmPlatform get _platform => WarmAlarmPlatform.instance;

  static bool _isValidVolume(double value) => value.isFinite && value >= 0 && value <= 1;

  /// Initializes the platform implementation and recovers its stored schedules.
  static Future<void> init() => _platform.init();

  /// Starts a custom Live Activity on a configured iOS host.
  static Future<WarmAlarmLiveActivityResult> startLiveActivity(WarmAlarmLiveActivityState state) =>
      _platform.startLiveActivity(state);

  /// Updates displayed content without changing the alarm schedule.
  static Future<WarmAlarmLiveActivityResult> updateLiveActivity(
    String activityId,
    WarmAlarmLiveActivityState state,
  ) => _platform.updateLiveActivity(activityId, state);

  /// Ends the custom Live Activity identified by [activityId].
  static Future<WarmAlarmLiveActivityResult> endLiveActivity(String activityId) =>
      _platform.endLiveActivity(activityId);

  /// Prepares a complete iOS AlarmKit sound from a recording and optional tone.
  /// Pass the returned path to [WarmAlarmAudio.systemSoundFilePath] and retain normal audio inputs for fallback.
  /// Returns null on unsupported backends; preparation failures complete with an error.
  static Future<String?> prepareSystemSound({
    required String primaryFilePath,
    String? backgroundAssetPath,
  }) => _platform.prepareSystemSound(
    primaryFilePath: primaryFilePath,
    backgroundAssetPath: backgroundAssetPath,
  );

  /// Returns a runtime snapshot of support for each alarm feature.
  /// Values can depend on host configuration and authorization, including iOS AlarmKit authorization.
  /// Query [getReadiness] as well before scheduling; support alone does not guarantee delivery.
  static Future<WarmAlarmCapabilities> getCapabilities() => _platform.getCapabilities();

  /// Returns the notification, exact-alarm, and full-screen permission snapshot.
  static Future<WarmAlarmPermissionState> getPermissionState() => _platform.getPermissionState();

  /// Returns the current readiness level and the reasons reported by the platform.
  /// A ready snapshot is not a guarantee that a future alarm will fire.
  /// Not every reason has a supported settings action.
  static Future<WarmAlarmReadiness> getReadiness() => _platform.getReadiness();

  /// Requests notification permission where supported and waits for the user's response.
  /// Inspect the returned permission state; a completed action does not imply permission was granted.
  static Future<WarmAlarmRemediationResult> requestNotificationPermission() =>
      _platform.requestNotificationPermission();

  /// Opens native settings for [reason] where supported.
  /// Returns when the platform accepts the request, before the user changes settings.
  /// Query [getReadiness] and [getCapabilities] again when the app resumes.
  static Future<WarmAlarmRemediationResult> openReadinessSettings(
    WarmAlarmReadinessReason reason,
  ) => _platform.openReadinessSettings(reason);

  /// Validates [schedule] and forwards it to the current platform.
  /// Invalid one-time dates, recurrence weekdays, durations, volumes, or fade-step ordering complete with [ArgumentError] before a platform call.
  /// Recurring schedules may use a past anchor date.
  ///
  /// Inspect the returned readiness and warning even when scheduling succeeds.
  /// Apple platforms return [WarmAlarmWarningCode.unsupportedWakeCheck] when wake-check was requested.
  /// Other native warnings can have no code, and warnings do not cover every ignored option.
  static Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async {
    if (schedule.recurrence == null &&
        schedule.scheduledAt.millisecondsSinceEpoch <= DateTime.now().millisecondsSinceEpoch) {
      throw ArgumentError.value(
        schedule.scheduledAt,
        'schedule.scheduledAt',
        'must be strictly in the future for a one-time schedule',
      );
    }
    final weekdays = schedule.recurrence?.weekdays;
    if (weekdays != null &&
        (weekdays.isEmpty ||
            weekdays.any(
              (weekday) => weekday < DateTime.monday || weekday > DateTime.sunday,
            ))) {
      throw ArgumentError.value(
        weekdays,
        'schedule.recurrence.weekdays',
        'must contain ISO weekdays from 1 to 7',
      );
    }
    if (schedule.snooze case final snooze? when snooze.duration.isNegative) {
      throw ArgumentError.value(
        snooze.duration,
        'schedule.snooze.duration',
        'must not be negative',
      );
    }
    if (schedule.wakeCheck case final wakeCheck? when wakeCheck.checkDelay.isNegative) {
      throw ArgumentError.value(
        wakeCheck.checkDelay,
        'schedule.wakeCheck.checkDelay',
        'must not be negative',
      );
    }
    if (schedule.wakeCheck?.retriggerDelay case final retriggerDelay? when retriggerDelay.isNegative) {
      throw ArgumentError.value(
        retriggerDelay,
        'schedule.wakeCheck.retriggerDelay',
        'must not be negative',
      );
    }
    if (schedule.wakeCheck?.maxRetriggers case final maxRetriggers? when maxRetriggers < 0) {
      throw ArgumentError.value(
        maxRetriggers,
        'schedule.wakeCheck.maxRetriggers',
        'must not be negative',
      );
    }
    if (schedule.audio.fadeInDuration case final fadeInDuration? when fadeInDuration.isNegative) {
      throw ArgumentError.value(
        fadeInDuration,
        'schedule.audio.fadeInDuration',
        'must not be negative',
      );
    }
    if (schedule.audio.volume case final volume? when !_isValidVolume(volume)) {
      throw ArgumentError.value(
        volume,
        'schedule.audio.volume',
        'must be from 0 to 1',
      );
    }
    int? previousFadeStepMillis;
    for (final fadeStep in schedule.audio.fadeSteps ?? const <WarmAlarmVolumeFadeStep>[]) {
      if (fadeStep.time.isNegative) {
        throw ArgumentError.value(
          fadeStep.time,
          'schedule.audio.fadeSteps.time',
          'must not be negative',
        );
      }
      final fadeStepMillis = fadeStep.time.inMilliseconds;
      if (previousFadeStepMillis != null && fadeStepMillis <= previousFadeStepMillis) {
        throw ArgumentError.value(
          fadeStep.time,
          'schedule.audio.fadeSteps.time',
          'must be strictly increasing at millisecond precision',
        );
      }
      previousFadeStepMillis = fadeStepMillis;
      if (!_isValidVolume(fadeStep.volume)) {
        throw ArgumentError.value(
          fadeStep.volume,
          'schedule.audio.fadeSteps.volume',
          'must be from 0 to 1',
        );
      }
    }
    return await _platform.scheduleAlarm(schedule);
  }

  /// Cancels the alarm identified by [id] on the current platform.
  static Future<void> cancelAlarm(int id) => _platform.cancelAlarm(id);

  /// Cancels all alarms managed by the current platform implementation.
  static Future<void> cancelAllAlarms() => _platform.cancelAllAlarms();

  /// Returns alarm snapshots from the platform's schedule store.
  /// Use [getAlarm] to select a snapshot whose scheduled time is still in the future.
  static Future<List<WarmAlarmSnapshot>> getScheduledAlarms() => _platform.getScheduledAlarms();

  /// Emits the lifecycle events reported by the current platform and backend.
  /// Buffered events can be replayed after a listener attaches or the engine reconnects.
  static Stream<WarmAlarmEvent> get events => _platform.events;

  /// Reports whether [id], or any alarm when omitted, is currently ringing.
  static Future<bool> isRinging({int? id}) => _platform.isRinging(id: id);

  /// Configures the platform's app-termination warning text.
  static Future<void> setKillWarning({
    required String title,
    required String body,
  }) => _platform.setKillWarning(title: title, body: body);

  /// Clears the configured app-termination warning.
  static Future<void> clearKillWarning() => _platform.clearKillWarning();

  /// Reports whether a stored alarm has a scheduled time strictly after now.
  /// This checks snapshot timestamps, not the current ringing state.
  static Future<bool> hasAlarm() async {
    final now = DateTime.now();
    return (await getScheduledAlarms()).any((a) => a.scheduledAt.isAfter(now));
  }

  /// Returns the snapshot for [id] only when its scheduled time is strictly after now.
  /// Returns null for an absent alarm or a snapshot at or before now.
  static Future<WarmAlarmSnapshot?> getAlarm(int id) async {
    final now = DateTime.now();
    final alarms = await getScheduledAlarms();
    for (final alarm in alarms) {
      if (alarm.id == id && alarm.scheduledAt.isAfter(now)) return alarm;
    }
    return null;
  }
}
