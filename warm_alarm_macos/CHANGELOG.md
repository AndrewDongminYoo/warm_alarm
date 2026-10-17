# 0.1.6

- Ignore a default tap on an occurrence the foreground already handled, so the tap neither restarts playback nor emits a duplicate `WarmAlarmFired`, including for alarms that fell back to the notification sound.
- Preserve host notification categories and apply distinct custom Stop/Snooze titles in the User Notifications backend.
- Report missing or failed custom audio and request notification sound for foreground fallback.
- Scope Stop and Snooze playback teardown to the matching alarm occurrence, and let an accepted delivery replace earlier playback before resolving its own source.
- Reject actions from replaced notification generations and commit Snooze only after successful registration, with previous-request recovery on failure.
- Record stopped recurring occurrences so a retained notification cannot snooze or replay them.
- Restore native default sound for foreground notifications when no custom player owns audio.
- Preserve unrelated host notifications during cancellation and forward their delegate callbacks without replacing host presentation or completion behavior.
- Validate foreground notification ownership and suppress cancelled or superseded deliveries before playback starts.
- Stop active playback on cancellation and serialize startup with cancellation so stale callbacks cannot restart audio.
- Restore the previous schedule and exact pending requests when replacement registration fails, and report incomplete recovery as a scheduling rollback failure.
- Clarify kill-warning triggers and pending-only cancellation on reactivation.
- Require platform interface 0.1.7 for the coordinated 0.1.7 / 0.1.8 release.

# 0.1.5

- Report an unsupported wake-check request in the typed schedule warning while preserving native warning text.
- Require platform interface 0.1.5 for the warning code.

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
