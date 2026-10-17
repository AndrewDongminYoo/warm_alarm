# 0.1.5

- Preserve completed alarm notifications after service exit across supported Android versions, removing stale controls and full-screen intent.
- Ignore locked-boot broadcasts below API 24 before accessing stored alarms; ordinary boot recovery remains available on API 19–23.
- Use supported inexact wake-check scheduling on API 19–22 and the legacy alarm audio stream on API 19–20.
- Use the API 19–22 exact-alarm API for initial scheduling, initialization recovery, and boot recovery while retaining modern exact/inexact scheduling and warnings.
- Release the previous player, callbacks, and vibration before an overlapping alarm starts, including repeated delivery for the same alarm ID.
- Attempt to release a newly allocated player when initialization fails, preserving the original playback error if cleanup also fails.
- Reject alarm IDs outside the signed 32-bit range instead of truncating them, and keep alarm and wake-check PendingIntent identities distinct.
- Clarify kill-warning triggers, notification dismissal, and the Android alarm ID contract.
- Require platform interface 0.1.7 for the coordinated 0.1.7 / 0.1.8 release.

# 0.1.4

- Require platform interface 0.1.5 for the coordinated wake-check warning release.

# 0.1.3

- Persist native alarm events until Dart acknowledges delivery, with bounded replay and corrupt-record recovery.
- Recover malformed schedule storage by replacing unreadable root data or removing unreadable records while retaining and persisting valid schedules.
- Honor Android alarm vibration and stop it with every playback teardown path.
- Select a single audio source with local-file precedence, apply `loop` to files and assets, and change system alarm volume only when `volumeEnforced` is enabled.

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
