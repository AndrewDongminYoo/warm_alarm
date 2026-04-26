import 'package:warm_alarm_platform_interface/src/models/warm_alarm_readiness.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

final class WarmAlarmScheduleResult {
  const WarmAlarmScheduleResult({
    required this.alarmId,
    required this.readiness,
    this.warning,
  });

  final int alarmId;
  final WarmAlarmReadiness readiness;
  final WarmAlarmWarning? warning;
}
