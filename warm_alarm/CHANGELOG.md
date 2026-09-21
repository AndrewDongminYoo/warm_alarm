# Unreleased

- Expose opt-in Live Activity start, update, and end operations.
- Retain native lifecycle events until Dart acknowledges delivery and replay pending events during initialization.
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
