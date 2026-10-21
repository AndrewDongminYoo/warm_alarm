# Unreleased

- Add `WarmAlarmScheduleResult.warnings`, which lists every scheduling warning in detection order.
  `warning` stays and returns the first entry, so existing callers and implementations keep working.

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
