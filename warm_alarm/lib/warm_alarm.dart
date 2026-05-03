import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

export 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarm {
  static WarmAlarmPlatform get _platform => WarmAlarmPlatform.instance;

  static Future<void> init() => _platform.init();

  static Future<WarmAlarmCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  static Future<WarmAlarmPermissionState> getPermissionState() =>
      _platform.getPermissionState();

  static Future<WarmAlarmReadiness> getReadiness() => _platform.getReadiness();

  static Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) => _platform.scheduleAlarm(schedule);

  static Future<void> cancelAlarm(int id) => _platform.cancelAlarm(id);

  static Future<void> cancelAllAlarms() => _platform.cancelAllAlarms();

  static Future<List<WarmAlarmSnapshot>> getScheduledAlarms() =>
      _platform.getScheduledAlarms();

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
