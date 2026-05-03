import 'package:warm_alarm_platform_interface/src/models/warm_alarm_audio.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_notification.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_schedule.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_wake_check.dart';

final class WarmAlarmSnapshot {
  const WarmAlarmSnapshot({
    required this.id,
    required this.scheduledAt,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
    this.wakeCheck,
    this.payload,
    this.androidFullScreenIntent = true,
  });

  final int id;
  final DateTime scheduledAt;
  final WarmAlarmNotification notification;
  final WarmAlarmAudio audio;
  final WarmAlarmRecurrence? recurrence;
  final WarmAlarmSnooze? snooze;
  final WarmAlarmWakeCheck? wakeCheck;
  final String? payload;

  /// Android only — whether full-screen intent was used for this alarm.
  final bool androidFullScreenIntent;
}
