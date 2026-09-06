# 0.1.2

- Own the fallback notification chain. Each alarm now registers a finite chain of follow-up requests behind its primary notification, and the plugin keeps that chain's whole lifecycle (registration, replacement, suppression, and teardown) in one place instead of leaving stray requests behind after a dismissal, a snooze, or a recurrence stop.
- Budget the 64 pending-request limit before scheduling. The plugin counts every pending request for the app, keeps all primary and per-weekday requests, and adds the longest fallback prefix that still fits. The schedule result carries a warning when a fallback is omitted, and scheduling fails without replacing the prior schedule when the primary or weekday requests themselves do not fit. A configured kill warning reserves one slot, and enabling it fails when no slot is free.
- Reject notification actions that no longer belong to the alarm they arrive for. Every request now carries the occurrence and generation it was registered under, so a stop or snooze tapped against an occurrence that was already replaced, canceled, or superseded no longer mutates the schedule that took its place. A delayed snooze action for an occurrence that is still current is still honoured.
- Persist a recurring alarm's wall-clock hour and minute, and migrate an existing schedule that predates the field by reading it back from its own pending `UNCalendarNotificationTrigger`. Recovery used to derive the time from the recomputed fire date, which drifted the series across a date line or after an expired snooze.
- Restore the snooze chain when registration fails partway. A snooze intent is persisted before its requests are registered and rolled back asynchronously when registration cannot complete, so a failed snooze no longer leaves the alarm without either its snooze or its original fallback coverage. Recurrence actions remain available while a snooze is active.
- Complete notification and snooze actions on the platform thread, and dispatch pending-limit failures on the main thread, so replies no longer cross threads on their way back to Dart.
- Serialize every notification mutation through one queue. Foreground delivery validation, fallback audio, and dismissal now run in a defined order instead of racing each other.

# 0.1.1

- Add notification authorization and notification-settings remediation.

# 0.1.0+1

- Initial release of this plugin.
