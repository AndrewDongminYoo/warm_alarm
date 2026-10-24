# 0.2.1

- Add `WarmAlarm.stopAlarm(id)`, which stops a ringing alarm through the same path as its notification's Stop action, so an app that dismisses from its own screen still starts the Android wake-check.
  It returns false and changes nothing when the alarm is not ringing, and always on iOS and macOS, which keep the app's own dismissal path.
- Require platform interface 0.2.2 and Android 0.1.8, the first releases that declare and implement `stopAlarm`.

# 0.2.0

- **Breaking:** Re-export platform interface 0.2.1, whose `WarmAlarmWarningCode` gains `unsupportedFadeIn`; code that switches exhaustively over `WarmAlarmWarningCode` needs a case for the new value.
- Require Android 0.1.7, iOS 0.1.14, and macOS 0.1.9: every platform now applies `fadeInDuration` on its plugin player, and iOS and macOS report `unsupportedFadeIn` when the system plays the alarm.
- Android reads the `WarmAlarmWakeCheck` prompt text (`title`, `body`, `confirmActionTitle`), reports `batteryOptimizationMayDelay` readiness on API 23 and later, and opens the battery optimization settings list.

# 0.1.9

- Require platform interface 0.1.8, Android 0.1.6, iOS 0.1.13, and macOS 0.1.8 so consumers receive separate scheduling warnings.
- Preserve every warning through the facade while the legacy `warning` getter remains the first entry or null.
- Iterate warning lists in the quick-start examples and document the bundled example screen's first-warning-only compatibility behavior.

# 0.1.8

- Align public API tables with asynchronous signatures, complete model fields, and Live Activity operations.
- Document event timestamps and the optional payloads exposed by fired, stopped, snoozed, and retriggered events.
- Clarify kill-warning configuration, platform lifecycle triggers, and readiness demo CI coverage.
- Require platform interface 0.1.7, Android 0.1.5, iOS 0.1.12, and macOS 0.1.6 so apps receive the alarm action, audio failure, and legacy Android fixes.

# 0.1.7

- Publish expanded API documentation for capabilities, readiness, and scheduling warnings.
- Show readiness reasons, warning codes, and full warning messages in the example, distinguishing unclassified warnings from no warning.
- Update the example and readiness action SDK requirements to Dart `^3.13.5` and Flutter `^3.47.7`.
- Require platform interface 0.1.6 so re-exported model documentation includes the null-code and null-warning semantics.

# 0.1.6

- Surface typed warnings when iOS or macOS ignores a requested wake-check while retaining native scheduling warnings.
- Require the platform interface and implementations published for the wake-check warning contract.

# 0.1.5

- Expose opt-in Live Activity start, update, and end operations.
- Require the published platform releases that retain native lifecycle events until Dart acknowledges delivery and replay pending events during initialization.
- Reject one-time schedules whose `scheduledAt` is not strictly future at millisecond precision with `ArgumentError` named `schedule.scheduledAt`.
- Reject audio fade steps with duplicate, decreasing, or same-millisecond timestamps with `ArgumentError` named `schedule.audio.fadeSteps.time`.
- Clarify custom audio source precedence, native fallback sounds, looping, volume enforcement, fade controls, and Apple background-haptics limitations.

# 0.1.4

- Expose granular iOS notification settings through alarm readiness results.
- Require the iOS implementation and platform interface that support Time Sensitive delivery and notification-settings remediation.

# 0.1.3

- Expose system-sound preparation for recording-only and combined voice alarms on configured iOS AlarmKit hosts.
- Require the iOS implementation and platform interface that support system sound overrides and playback ownership.

# 0.1.2

- Add APIs that request notification authorization or open supported readiness settings.

# 0.1.1

- Clarify that warm_alarm is an independent Flutter plugin extracted from WarmWake.

# 0.1.0+1

- Initial release of this plugin.
