# 0.1.4

- Resolve Flutter audio assets from the embedded App.framework while retaining the main-bundle fallback.

# 0.1.3

- Persist lifecycle events before Dart dispatch and retry acknowledged delivery during initialization.
- Buffer events until the first Dart stream listener and preserve file-first custom audio selection.

# 0.1.2

- Persist a recurring alarm's wall-clock hour and minute so recovery re-registers the series at the time it was scheduled for. Recovery derived the time from the recomputed fire date, so a series recovered across a date line or after an expired snooze could come back at the wrong time.
- Migrate a stored schedule that predates those fields by reading the hour and minute back from its own pending `UNCalendarNotificationTrigger`, then saving the migrated schedule. An alarm scheduled by 0.1.1 keeps its time without being rescheduled.

# 0.1.1

- Add notification authorization remediation and explicit unsupported settings remediation.

# 0.1.0+1

- Initial release of this plugin.
