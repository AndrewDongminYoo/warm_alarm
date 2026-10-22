# warm_alarm_android

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

The Android implementation of [`warm_alarm`][warm_alarm_link].

This package is [endorsed][endorsed_link], which means you do **not** add it directly to your
`pubspec.yaml`. It is automatically included when you depend on `warm_alarm`.

---

## Platform capabilities

| Feature                   | Support    | Notes                                                                                                           |
| ------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------- |
| Notification scheduling   | ✅ Full    | `POST_NOTIFICATIONS` permission required                                                                        |
| Exact alarm scheduling    | ✅ Full    | `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`                                                                      |
| Background audio playback | ⚠️ Limited | Foreground service with `mediaPlayback` type                                                                    |
| Full-screen presentation  | ✅ Full    | `setFullScreenIntent`; per-alarm via `androidFullScreenIntent`; runtime-checked with `canUseFullScreenIntent()` |
| Wake-check                | ✅ Full    | Follow-up alarm verifies user is awake                                                                          |

---

## Scheduling warnings

Version 0.1.6 requires platform interface 0.1.8 and reports scheduling diagnostics through the read-only `WarmAlarmScheduleResult.warnings` list.
The legacy `warning` getter returns the first entry, or null when the list is empty.
An exact-alarm permission fallback produces one native warning with a null code; other native entries retain their order.
An empty list does not guarantee that every requested option was applied.
Earlier versions use the single-warning constructor.

## Native implementation

### Scheduling

Initial scheduling, initialization recovery, boot recovery, and rescheduling use the same version-aware policy.
On API 19–22, the plugin uses `AlarmManager.setExact()`.
On API 23 or later, it uses `setExactAndAllowWhileIdle()` when exact-alarm access is available.
On Android 12 or later without that access, it uses `setAndAllowWhileIdle()` and returns limited readiness plus a warning that the alarm may fire late.
`getPermissionState()` reports the current exact-alarm grant.
The manifest declares `SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM`; their grant rules and eligible uses differ, as described in [Android’s exact-alarm permission guidance](https://developer.android.com/develop/background-work/services/alarms).

Android alarm IDs must be signed 32-bit integers (`-2147483648` through `2147483647`, inclusive).
Negative IDs, including `-1`, are supported.
Scheduling or individually cancelling an out-of-range ID fails with `INVALID_ALARM_ID` before changing stored schedules or Android registrations.
Startup and boot recovery skip unsupported legacy IDs and emit a failed event with `invalidArguments`; the stored records remain available for inspection.
`cancelAllAlarms()` clears those records without looking up their truncated IDs, which could cancel a different supported alarm.
Already-aliased out-of-range registrations from older versions cannot be reconstructed independently; full 64-bit ID migration is not provided.

`requestNotificationPermission()` requests `POST_NOTIFICATIONS` on Android 13+.
On Android 12 and earlier there is no runtime notification permission to request, so the call reports `unsupported` and the caller should open notification settings instead.
`openReadinessSettings(reason)` opens notification, exact-alarm, or full-screen settings when the reported reason supports it.
The settings action returns when Android accepts the deep link.
Query readiness again after the app resumes.

### Alarm delivery

When the scheduled time arrives `WarmAlarmReceiver` receives the `com.andrew.alarm.ACTION_FIRE`
broadcast and starts `WarmAlarmForegroundService`. The service:

- Plays audio via `MediaPlayer` (local file, asset, or system default ringtone), using the legacy alarm stream on API 19–20 and audio attributes on API 21 or later
- Selects one audio source: a nonempty local file takes precedence, an asset is the direct-boot fallback when that file is unavailable before unlock, and the system alarm sound is used when neither path is configured
- Applies `loop` to the selected local file or asset without mixing sources
- Applies optional fade-in via a `Handler`-driven volume schedule
- Runs optional repeating vibration with the alarm and stops it on Stop, Snooze, playback failure, cancellation, or service destruction
- Posts the alarm notification with configurable Stop/Snooze actions
- Boosts and periodically enforces the maximum alarm stream volume only when `volumeEnforced` is enabled

Only one alarm plays at a time.
A newly fired alarm replaces the current playback, including another fire of the same alarm ID.
Replacement releases the previous player and clears its fade callbacks, vibration, and volume-enforcement timer before the next playback starts.
It does not perform a Stop or Snooze action on the replaced alarm's stored schedule.

When `notification.keepNotificationAfterAlarmEnds` is `true`, Stop and Snooze retain the notification content after the service exits.
API 24 and later detach it from the foreground-service lifetime; API 19–23 remove the foreground notification and post an ordinary replacement.
The retained notification is dismissible and has no Stop/Snooze actions or full-screen intent.
The ordinary replacement uses low priority with sound, vibration, and default alerts disabled.
With retention disabled, completion removes the foreground notification.

### Wake-check

When `WarmAlarmWakeCheck` is configured, stopping the primary alarm schedules a secondary alarm for `checkDelay` later.
The check uses inexact `AlarmManager.set()` on API 19–22 and `setAndAllowWhileIdle()` on API 23 or later.
When `ACTION_WAKE_CHECK_FIRE` arrives, the receiver shows the wake-check prompt and schedules a retrigger when `retriggerDelay` is configured, up to `maxRetriggers` times.
`ACTION_WAKE_CHECK_DISMISS` cancels the follow-up chain.

A retrigger and the regular alarm are separate `PendingIntent`s.
`AlarmManager` matches on request code plus `Intent.filterEquals`, which ignores extras, so a shared identity let arming a retrigger re-target the pending next occurrence and let a dismiss cancel it.
Only the retrigger carries a `warm-alarm://<package>/alarm/<id>/retrigger` data Uri; the regular alarm keeps the data-less identity it had before 0.1.2, so an alarm scheduled by an older install stays cancellable after an update.
This compatibility applies to IDs in the supported range.
Stop and Snooze service actions use an ID-scoped URI and distinct actions, so their identities do not depend on multiplying an ID into a request code.
Finishing a wake check clears a recurring alarm's retrigger count and removes the stored schedule only for a one-shot alarm.

`filterEquals` cannot be exercised from the JVM unit tests.
`WarmAlarmPendingIntentsInstrumentedTest` asserts it against the real framework registry on API 19, 22, and 29 emulators in CI.
`WarmAlarmDeliveryInstrumentedTest` registers a native alarm, observes receiver delivery and audio initialization, sends Stop, and waits for the wake-check event on the same images.
These tests exercise native code without starting a Flutter engine; they do not establish that a current Flutter application can run on API 19.
The test APK excludes Flutter's API 21 image-decoding dependency and does not override dependency minimum SDK requirements.
What that test does not cover is the scenario around it, which is still a device check: schedule a recurring alarm, let the wake check fire, tap the dismiss action, then confirm the next occurrence is still listed by `adb shell dumpsys alarm | grep <package>`.
Read `adb shell dumpsys activity intents` rather than `dumpsys alarm` when the question is which `PendingIntent` is which: only the former prints `requestCode` and the intent's data Uri.

### Recurrence

Weekly recurrence is re-armed on fire: `AlarmManager` is single-shot, so when a recurring alarm
fires, `WarmAlarmReceiver` computes the next matching weekday occurrence
(`WarmAlarmRecurrence.nextOccurrence`, same time-of-day, strictly after now) and re-arms it, updating
the stored `scheduledAtMillis`. The re-arm runs in the receiver without a Flutter engine, so the
series survives even when the app process is dead. Dismissing an alarm ends only the current
occurrence; `cancelAlarm(id)` tears down the series.

### Boot persistence

`WarmAlarmBootReceiver` handles `BOOT_COMPLETED` (via the `RECEIVE_BOOT_COMPLETED` permission) to reschedule alarms lost when the device restarted.
It accepts `LOCKED_BOOT_COMPLETED` only from API 24, where Direct Boot is supported, and restores alarms from device-protected storage before first unlock.
On API 19–23, the locked-boot action is ignored before reading or modifying stored alarms; ordinary boot recovery remains supported.
If the stored schedule list is unreadable, the store replaces it with an empty list.
If individual records are unreadable, the store retains valid schedules and persists the repaired set through the same device-protected and credential-protected storage path.

### Kill warning

`setKillWarning(title, body)` stores the warning text without posting a notification.
When Android calls the service's `onTaskRemoved` callback, such as when the app is swiped from recents, the plugin posts the configured warning if an alarm is scheduled in the future or is currently ringing.
The warning notification has auto-cancel enabled and is not marked ongoing.
`clearKillWarning()` removes the stored text and disables future warning posts; it does not dismiss an already posted warning.
Warning delivery depends on notification permission and the task-removal callback being delivered.

---

## Required permissions

The following permissions are declared in the plugin's `AndroidManifest.xml` and merged
automatically into your app's manifest:

```plaintext
SCHEDULE_EXACT_ALARM       — exact alarm scheduling (user-granted on Android 12+)
USE_EXACT_ALARM            — exact alarm scheduling (system-granted for alarm-category apps)
RECEIVE_BOOT_COMPLETED     — reschedule alarms after device reboot
POST_NOTIFICATIONS         — show alarm and kill-warning notifications (Android 13+)
USE_FULL_SCREEN_INTENT     — launch the full-screen alarm UI over the lock screen (Android 14+)
VIBRATE                    — haptic feedback during alarm
FOREGROUND_SERVICE         — run WarmAlarmForegroundService
FOREGROUND_SERVICE_MEDIA_PLAYBACK — declare mediaPlayback foreground service type
```

---

## Pigeon wire layer

All Dart ↔ Kotlin communication is generated by [Pigeon][pigeon_link]. The schema lives in
`pigeons/messages.dart`; generated outputs (`Messages.g.kt`, `lib/src/messages.g.dart`) are never
hand-edited. Run `melos run generate` after any schema change.

---

## License

BSD-3-Clause — Copyright (c) 2026, Dongmin Yu. See [LICENSE](LICENSE) for details.

<!-- links -->

[warm_alarm_link]: https://pub.dev/packages/warm_alarm
[endorsed_link]: https://flutter.dev/to/endorsed-federated-plugin
[license_badge]: https://img.shields.io/badge/license-BSD--3--Clause-blue.svg
[license_link]: https://opensource.org/licenses/BSD-3-Clause
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[pigeon_link]: https://pub.dev/packages/pigeon
