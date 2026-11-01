import 'package:warm_alarm_platform_interface/src/models/warm_alarm_audio.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_notification.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_wake_check.dart';

final class WarmAlarmRecurrence {
  const WarmAlarmRecurrence({
    required this.weekdays,
  });

  final List<int> weekdays;
}

/// Configures the Snooze action of an alarm's notification.
///
/// No platform reads [maxCount] in warm_alarm_platform_interface 0.3.0; the platform packages honor it in a later
/// release, and until then a notification keeps its Snooze action on every ring.
final class WarmAlarmSnooze {
  const WarmAlarmSnooze({
    required this.duration,
    this.maxCount,
  });

  /// How long a snoozed alarm waits before it rings again.
  final Duration duration;

  /// How many times the person can snooze one occurrence of this alarm from its notification.
  ///
  /// When null there is no limit, and a notification that has a Snooze action offers it on every ring.
  /// On Android a notification has one only when `WarmAlarmNotification.snoozeActionTitle` is non-null.
  /// When 0, the notification has no Snooze action.
  /// The count starts again when a new occurrence rings, and when the alarm is scheduled again or cancelled.
  /// A host that schedules its own snooze ring should pass the number of snoozes left, so the limit still holds.
  /// A backend whose snooze is performed by the system reports [WarmAlarmWarningCode.unsupportedSnoozeLimit]
  /// when it cannot honor a non-null value.
  final int? maxCount;
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

  final int id;
  final DateTime scheduledAt;
  final WarmAlarmNotification notification;
  final WarmAlarmAudio audio;
  final WarmAlarmRecurrence? recurrence;
  final WarmAlarmSnooze? snooze;
  final WarmAlarmWakeCheck? wakeCheck;
  final String? payload;

  /// Android only — whether to present as a full-screen intent notification.
  final bool androidFullScreenIntent;
}
