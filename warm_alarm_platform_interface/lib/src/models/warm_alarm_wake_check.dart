/// Configures a follow-up prompt after the user stops an alarm, and the retrigger when nobody answers.
///
/// warm_alarm_android 0.1.7 and later read [title], [body] and [confirmActionTitle] and return them from
/// `getScheduledAlarms`; earlier Android releases keep the default prompt text and return these fields null.
/// iOS and macOS do not support wake-check and ignore these fields.
final class WarmAlarmWakeCheck {
  const WarmAlarmWakeCheck({
    required this.checkDelay,
    this.retriggerDelay,
    this.maxRetriggers = 1,
    this.title,
    this.body,
    this.confirmActionTitle,
  });

  final Duration checkDelay;
  final Duration? retriggerDelay;
  final int? maxRetriggers;

  /// Title of the wake-check prompt.
  ///
  /// When null, the prompt keeps the platform default, which is the alarm's `WarmAlarmNotification.title`.
  /// Platforms that do not support wake-check ignore this field.
  final String? title;

  /// Body text of the wake-check prompt, such as a localized "Are you awake?".
  ///
  /// When null, the prompt keeps the platform default English body.
  /// Platforms that do not support wake-check ignore this field.
  final String? body;

  /// Label of the action that confirms the user is awake.
  ///
  /// When null, the prompt keeps the platform default, which is the alarm's `WarmAlarmNotification.stopActionTitle`,
  /// or an English default when that is also null.
  /// Set this when the stop label does not read as a wake confirmation, such as "Dismiss alarm".
  /// Platforms that do not support wake-check ignore this field.
  final String? confirmActionTitle;
}
