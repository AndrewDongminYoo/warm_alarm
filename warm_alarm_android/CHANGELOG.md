# 0.1.2

- Give a wake-check retrigger its own `PendingIntent` identity. It shared the regular alarm's, so arming a retrigger re-targeted the pending next occurrence and dismissing a wake check cancelled it.
- Keep a recurring alarm's stored schedule when a wake check finishes. Only a one-shot alarm's schedule is removed.
- Cancel both alarm identities from `cancelAlarm` and `cancelAllAlarms`.
- End any wake-check cycle still in flight when an alarm is replaced, cancelled, or finishes its last retrigger. `WarmAlarmPendingIntents.endWakeCheckCycle` cancels the pending check, the retrigger, and the prompt, and resets the retrigger count, so no teardown path can leave one part of a cycle armed against a schedule it no longer belongs to.
- Reset the retrigger count once a recurring alarm exhausts `maxRetriggers`. It stayed at the maximum, so every later occurrence skipped its wake check.
- Leave the stored schedule alone when a wake check finishes and it could not be read back. A null read is ambiguous, and `remove()` persists the map it just read, so removing on a read that came back empty would write an empty list over every schedule.

# 0.1.1

- Add notification authorization and supported readiness-settings remediation.
- Report `unsupported` when notification authorization is requested below Android 13.

# 0.1.0+1

- Initial release of this plugin.
