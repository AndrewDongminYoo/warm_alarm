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

## Native implementation

### Scheduling

Alarms are scheduled via `AlarmManager.setExactAndAllowWhileIdle()` so they fire even when the
device is in Doze mode. The exact-alarm permission (either `USE_EXACT_ALARM` for system apps or
`SCHEDULE_EXACT_ALARM` with user approval) is declared in the manifest and checked at runtime
through `getPermissionState()`.

`requestNotificationPermission()` requests `POST_NOTIFICATIONS` on Android 13+.
On Android 12 and earlier there is no runtime notification permission to request, so the call reports `unsupported` and the caller should open notification settings instead.
`openReadinessSettings(reason)` opens notification, exact-alarm, or full-screen settings when the reported reason supports it.
The settings action returns when Android accepts the deep link.
Query readiness again after the app resumes.

### Alarm delivery

When the scheduled time arrives `WarmAlarmReceiver` receives the `com.andrew.alarm.ACTION_FIRE`
broadcast and starts `WarmAlarmForegroundService`. The service:

- Plays audio via `MediaPlayer` (local file, asset, or system default ringtone)
- Applies optional fade-in via a `Handler`-driven volume schedule
- Posts the alarm notification with configurable Stop/Snooze actions
- Optionally enforces volume if the device is set to silent

### Wake-check

When `WarmAlarmWakeCheck` is configured, a secondary alarm is scheduled for `checkDelay` after the
primary alarm fires. If `ACTION_WAKE_CHECK_FIRE` arrives without the user having dismissed the
primary alarm, the alarm retriggers (up to `maxRetriggers` times at `retriggerDelay` intervals).
`ACTION_WAKE_CHECK_DISMISS` cancels the follow-up chain.

### Recurrence

Weekly recurrence is re-armed on fire: `AlarmManager` is single-shot, so when a recurring alarm
fires, `WarmAlarmReceiver` computes the next matching weekday occurrence
(`WarmAlarmRecurrence.nextOccurrence`, same time-of-day, strictly after now) and re-arms it, updating
the stored `scheduledAtMillis`. The re-arm runs in the receiver without a Flutter engine, so the
series survives even when the app process is dead. Dismissing an alarm ends only the current
occurrence; `cancelAlarm(id)` tears down the series.

### Boot persistence

`WarmAlarmBootReceiver` handles `BOOT_COMPLETED` and `LOCKED_BOOT_COMPLETED` broadcasts (via
`RECEIVE_BOOT_COMPLETED` permission) to reschedule any alarms that were lost when the device
restarted. It is `directBootAware`, so alarms scheduled before first unlock are restored from
device-protected storage.

### Kill warning

`setKillWarning(title, body)` posts a persistent, non-dismissible notification to discourage users
from force-quitting the app before an alarm fires. Call `clearKillWarning()` to remove it.

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
