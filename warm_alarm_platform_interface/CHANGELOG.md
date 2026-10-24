# 0.2.1

- Document that warm_alarm_android 0.1.7 reads the `WarmAlarmWakeCheck` prompt fields `title`, `body` and `confirmActionTitle`, and that iOS and macOS ignore them.
- Document that warm_alarm_android 0.1.7, warm_alarm_ios 0.1.14 and warm_alarm_macos 0.1.9 apply `fadeInDuration` on the plugin player, and that the Apple packages report `unsupportedFadeIn` when the system plays the alarm.

# 0.2.0

- **Breaking:** Add `WarmAlarmWarningCode.unsupportedFadeIn` for a backend that ignored `fadeInDuration` because it did not own playback or does not support a fade.
  Code that switches exhaustively over `WarmAlarmWarningCode` needs a case for the new value, so this release is a minor bump that `^0.1.x` constraints do not select.
- Add optional `title`, `body` and `confirmActionTitle` to `WarmAlarmWakeCheck` so a host can word and localize the wake-check prompt.
  Null keeps the current prompt text, so existing callers are unaffected; the platform packages read these fields in a later release.
- Document that `fadeSteps` wins over `fadeInDuration` when both are set, and that `fadeInDuration` alone is a linear fade from silence to `volume`, or to 1.0 when `volume` is null.
- Document that Android readiness checks the battery optimization exemption and reports `batteryOptimizationMayDelay` from API 23.

# 0.1.8

- Add `WarmAlarmScheduleResult.warnings`, which lists every scheduling warning in detection order.
  `warning` stays and returns the first entry, so existing callers and implementations keep working.
- Add `WarmAlarmScheduleResult.withWarnings` to copy a warning list into a stable, read-only result while preserving the existing const constructor.

# 0.1.7

- Complete the public contract reference with Live Activity operations, notification settings, warning and failure models, and asynchronous return types.
- Clarify that kill-warning methods configure text rather than posting or removing notifications.

# 0.1.6

- Document readiness reasons and scheduling warning semantics in the public models.
- Clarify that a null warning code still represents a warning, and that a null scheduling warning does not guarantee every platform-specific option was applied.

# 0.1.5

- Add an optional warning code for wake-check requests that a platform cannot honor.

# 0.1.4

- Add opt-in Live Activity content and operation result models.
- Add inherited unsupported defaults for start, update, and end so existing platform subclasses remain compatible.

# 0.1.3

- Expose granular notification authorization and delivery settings through the optional readiness snapshot.

# 0.1.2

- Add optional system-sound preparation and an AlarmKit sound-file override without changing legacy audio inputs.
- Add actual system audio ownership to alarm snapshots, with a default of false for existing backends.

# 0.1.1

- Add the readiness remediation contract and result model.
  Both methods default to `unsupported`; the endorsed platform packages implement them in a
  release that depends on this version.

# 0.1.0+1

- Initial release.
