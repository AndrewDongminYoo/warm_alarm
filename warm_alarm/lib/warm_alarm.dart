import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

export 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarm {
  static WarmAlarmPlatform get _platform => WarmAlarmPlatform.instance;

  static Future<WarmAlarmCapabilities> getCapabilities() => _platform.getCapabilities();

  static Future<WarmAlarmPermissionState> getPermissionState() => _platform.getPermissionState();

  static Future<WarmAlarmReadiness> getReadiness() => _platform.getReadiness();

  static Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) => _platform.scheduleAlarm(schedule);

  static Future<void> cancelAlarm(int id) => _platform.cancelAlarm(id);

  static Future<void> cancelAllAlarms() => _platform.cancelAllAlarms();

  static Future<List<WarmAlarmSnapshot>> getScheduledAlarms() => _platform.getScheduledAlarms();

  static Stream<WarmAlarmEvent> get events => _platform.events;

  static Future<bool> isRinging({int? id}) => _platform.isRinging(id: id);
}
