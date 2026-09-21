import 'package:warm_alarm_platform_interface/src/models/warm_alarm_audio.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_notification.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_wake_check.dart';

final class WarmAlarmRecurrence {
  const WarmAlarmRecurrence({
    required this.weekdays,
  });

  final List<int> weekdays;
}

final class WarmAlarmSnooze {
  const WarmAlarmSnooze({
    required this.duration,
  });

  final Duration duration;
}

final class WarmAlarmSchedule {
  const WarmAlarmSchedule({
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

  /// App-assigned alarm identifier.
  final int id;

  /// One-time fire time or the local weekday/time anchor for a recurring alarm.
  ///
  /// One-time schedules must be strictly in the future at millisecond precision.
  /// Recurring schedules may use a past anchor because the next matching local weekday and time is scheduled.
  final DateTime scheduledAt;

  /// Notification content and actions for the alarm.
  final WarmAlarmNotification notification;

  /// Audio, volume, and vibration configuration for the alarm.
  final WarmAlarmAudio audio;

  /// Optional local-weekday recurrence.
  final WarmAlarmRecurrence? recurrence;

  /// Optional native snooze behavior.
  final WarmAlarmSnooze? snooze;

  /// Optional Android wake-check behavior.
  final WarmAlarmWakeCheck? wakeCheck;

  /// Optional app payload included in alarm events.
  final String? payload;

  /// Android only — whether to present as a full-screen intent notification.
  final bool androidFullScreenIntent;
}
