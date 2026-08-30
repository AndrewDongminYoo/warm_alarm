import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

export 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarm {
  static WarmAlarmPlatform get _platform => WarmAlarmPlatform.instance;

  static bool _isValidVolume(double value) => value.isFinite && value >= 0 && value <= 1;

  static Future<void> init() => _platform.init();

  static Future<WarmAlarmCapabilities> getCapabilities() => _platform.getCapabilities();

  static Future<WarmAlarmPermissionState> getPermissionState() => _platform.getPermissionState();

  static Future<WarmAlarmReadiness> getReadiness() => _platform.getReadiness();

  static Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async {
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
    for (final fadeStep in schedule.audio.fadeSteps ?? const <WarmAlarmVolumeFadeStep>[]) {
      if (fadeStep.time.isNegative) {
        throw ArgumentError.value(
          fadeStep.time,
          'schedule.audio.fadeSteps.time',
          'must not be negative',
        );
      }
      if (!_isValidVolume(fadeStep.volume)) {
        throw ArgumentError.value(
          fadeStep.volume,
          'schedule.audio.fadeSteps.volume',
          'must be from 0 to 1',
        );
      }
    }
    return _platform.scheduleAlarm(schedule);
  }

  static Future<void> cancelAlarm(int id) => _platform.cancelAlarm(id);

  static Future<void> cancelAllAlarms() => _platform.cancelAllAlarms();

  static Future<List<WarmAlarmSnapshot>> getScheduledAlarms() => _platform.getScheduledAlarms();

  static Stream<WarmAlarmEvent> get events => _platform.events;

  static Future<bool> isRinging({int? id}) => _platform.isRinging(id: id);

  static Future<void> setKillWarning({
    required String title,
    required String body,
  }) => _platform.setKillWarning(title: title, body: body);

  static Future<void> clearKillWarning() => _platform.clearKillWarning();

  static Future<bool> hasAlarm() async {
    final now = DateTime.now();
    return (await getScheduledAlarms()).any((a) => a.scheduledAt.isAfter(now));
  }

  static Future<WarmAlarmSnapshot?> getAlarm(int id) async {
    final now = DateTime.now();
    final alarms = await getScheduledAlarms();
    for (final alarm in alarms) {
      if (alarm.id == id && alarm.scheduledAt.isAfter(now)) return alarm;
    }
    return null;
  }
}
