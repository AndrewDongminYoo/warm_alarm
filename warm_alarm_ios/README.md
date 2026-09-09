# warm_alarm_ios

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

The iOS implementation of [`warm_alarm`][warm_alarm_link].

This package is [endorsed][endorsed_link], which means you do **not** add it directly to your
`pubspec.yaml`. It is automatically included when you depend on `warm_alarm`.

---

## Platform capabilities

| Feature                   | Support               | Notes                                                                |
| ------------------------- | --------------------- | -------------------------------------------------------------------- |
| Notification scheduling   | ✅ Full               | `UNUserNotificationCenter`                                           |
| Exact alarm scheduling    | ✅ Full or ⚠️ Limited | AlarmKit on configured iOS 26+ hosts; notification fallback          |
| Background audio playback | ⚠️ Limited            | `AVAudioSession` `.playback` applies only while the app process runs |
| Full-screen presentation  | ❌ None               | AlarmKit presents system UI; it does not open a Flutter screen       |
| Wake-check                | ❌ None               | iOS does not provide the Android wake-check flow                     |

**⚠️ Limited** means the alarm fires via a `UNUserNotificationCenter` notification. The app is not
guaranteed to launch automatically in the background — audio plays only after the user interacts
with the notification (or if the app is already in the foreground).

## AlarmKit opt-in

The plugin uses AlarmKit when the app runs on iOS 26 or later, the build SDK contains AlarmKit, the host app has a non-empty `NSAlarmKitUsageDescription`, and AlarmKit authorization is not denied.
The first AlarmKit schedule can show the system authorization prompt while the authorization state is `notDetermined`.
If AlarmKit is unavailable, unconfigured, or denied, the plugin uses the existing User Notifications backend.
If AlarmKit fails to schedule, the plugin removes any native alarm with the same stable ID before it installs the User Notifications fallback.
The scheduling call fails instead of installing a second backend when native cleanup cannot be confirmed.
`WarmAlarmScheduleResult.warning` identifies a runtime fallback caused by an AlarmKit scheduling error.

Add a usage description to the host app's `Info.plist`.

```xml
<key>NSAlarmKitUsageDescription</key>
<string>Allow alarms that you schedule in this app to alert you.</string>
```

`requestNotificationPermission()` requests User Notifications authorization only.
AlarmKit requests its own authorization when the app schedules its first native alarm.
If AlarmKit authorization is denied, `getPermissionState()` reports `exactAlarmGranted: false`, `getReadiness()` includes `exactAlarmPermissionDenied`, and `openReadinessSettings(exactAlarmPermissionDenied)` opens the app settings page.

### Snooze host requirement

AlarmKit implements `WarmAlarmSnooze.duration` as a post-alert countdown.
Apple requires a Widget Extension that supplies the corresponding Live Activity presentation when an alarm supports a countdown.
Declare `extension Never: @retroactive AlarmMetadata {}` in the Widget Extension and register an `ActivityConfiguration` for `AlarmAttributes<Never>`.
The plugin provides `nil` metadata through this module-independent type, so the extension does not need to link the plugin module.
After the extension is ready, enable Live Activities and the plugin opt-in in the app target's `Info.plist`.

```xml
<key>NSSupportsLiveActivities</key>
<true/>
<key>WarmAlarmAlarmKitLiveActivityEnabled</key>
<true/>
```

Without the extension and this opt-in, schedules with Snooze use the User Notifications fallback and return a warning.

### Schedule mapping

| `WarmAlarmSchedule` value                  | AlarmKit mapping                                                                     |
| ------------------------------------------ | ------------------------------------------------------------------------------------ |
| `id`                                       | Stable UUID derived from the signed 64-bit alarm ID                                  |
| `scheduledAt` without recurrence           | Fixed schedule that does not move after a time-zone change                           |
| `scheduledAt` with recurrence              | Local hour and minute for a relative weekly schedule                                 |
| `recurrence.weekdays`                      | ISO weekdays mapped to AlarmKit weekdays                                             |
| `notification.title`                       | Native alarm title                                                                   |
| `notification.stopActionTitle`             | Custom stop title on iOS 26.0; iOS 26.1+ uses the system stop control                |
| `notification.snoozeActionTitle`, `snooze` | Native countdown button and post-alert duration                                      |
| `audio.systemSoundFilePath`                | Complete sound prepared for AlarmKit; it takes priority over the normal audio inputs |
| `audio.filePath`, `audio.assetPath`        | File-first audio converted to a named CAF when no complete system sound is provided  |
| `notification.body`, `payload`             | Retained for the existing in-app and notification flow                               |

AlarmKit handles native Stop and Snooze actions without launching the Flutter process.
Those system actions cannot emit `WarmAlarmStopped` or `WarmAlarmSnoozed` while the app is not running.
On the next `initialize()`, the plugin emits one `WarmAlarmSnoozed` event for an unobserved countdown or paused state.
It emits `WarmAlarmStopped` when a missing AlarmKit one-shot has expired.

---

## Native implementation

### Scheduling

Configured iOS 26 or later hosts schedule alarms through `AlarmManager`.
Older and unconfigured hosts schedule `UNNotificationRequest` objects through `UNUserNotificationCenter`.
The plugin removes the other backend's requests only after it confirms the replacement or cleanup.
`initialize()` fails without adding fallback requests when the current AlarmKit inventory cannot be read.
The persisted backend marker lets a later authorization or host-configuration change remove an existing native alarm before it restores the notification fallback.
`getScheduledAlarms()` and `isRinging()` read AlarmKit state so native Stop, Snooze countdown fire dates, and alerting states are reflected in the public API.
Flutter cancellation uses AlarmKit `stop(id:)` while a native alarm is alerting and `cancel(id:)` for its other states.

### Audio

On configured AlarmKit hosts, call `prepareSystemSound` with a recording and an optional Flutter tone asset before scheduling.
The renderer preserves the recording length, repeats a shorter tone through the full recording, and mixes both sources at half gain.
Before decoding, it rejects inputs whose planned PCM buffers exceed 134,217,728 bytes in total.
The limit includes the source, converted audio, retained voice during background decoding, and input chunks; it does not measure codec-internal allocations.
It writes a unique PCM CAF under `Library/Sounds` with protection that permits access after the first device unlock.
Pass the returned path as `WarmAlarmAudio.systemSoundFilePath` and retain the normal audio inputs for User Notifications fallback.
Unsupported hosts return null.
Preparation errors fail the request instead of substituting a default sound.
Preparation runs on the existing serial mutation queue, away from the platform thread, and replies on the platform thread.
Prepared sounds are staging files and should be scheduled promptly.
Initialization removes unreferenced owned files last modified more than 24 hours ago after native state is reconciled or before the first AlarmKit authorization request.
Recent staging files and sounds referenced by stored alarms are retained.

After scheduling, read `WarmAlarmSnapshot.systemManagedAudio` before starting app audio.
It is true only when AlarmKit adopted a complete system sound; a requested override or capability check alone does not establish ownership.
Legacy `filePath` or `assetPath` inputs alone do not opt into this complete-sound contract, because the host may still play additional audio.
To prevent a second host player, prepare the full sound and pass it through `systemSoundFilePath`.
AlarmKit alerts do not start a second `AVAudioPlayer`.
The system controls repetition, volume, and Stop/Snooze; the normal `loop`, volume, and fade settings remain specific to the legacy player.

Keep prepared files immutable while any alarm references them.
Successful replacement, cancellation, one-shot Stop, and confirmed backend removal release unreferenced generated files.
Recurring Stop and Snooze retain their sound.
If native scheduling and rollback both fail, candidate files are retained because native ownership is uncertain.

The following behavior applies to the User Notifications backend.

When the notification action is handled, `WarmAlarmDelegate` starts `AVAudioPlayer` with the
configured audio source (a local file path or a Flutter asset). If neither is provided, no in-app
audio is played — the notification itself still plays the bundled `alarm_ring.caf` (or the system
default) sound. The `AVAudioSession` category is set to `.playback` (with `.mixWithOthers`) so the
audio continues even when the device is in Silent mode. An optional fade-in is applied by scheduling
discrete volume steps as `DispatchWorkItem`s (via `DispatchQueue.main.asyncAfter`), not a periodic
timer.

### Recurrence

Weekly recurrence uses one native `UNCalendarNotificationTrigger(repeats: true)` for each selected weekday.
Each request matches `DateComponents(weekday, hour, minute)` and uses the key `"{id}#{isoWeekday}"`.
The series recurs without a re-arm and survives app termination.
ISO weekdays (1 = Mon … 7 = Sun) are mapped to Apple's Calendar weekdays (1 = Sun … 7 = Sat).
Dismissing an alarm ends only the current occurrence.
`cancelAlarm(id)` removes every weekday request and tears down the series.
Each alarm also uses up to six slots for its finite fallback chain.
Before scheduling, the plugin counts all pending app requests against the iOS limit of 64 requests.
The plugin keeps every primary or weekday request and adds the longest fallback prefix that fits.
The schedule result contains a warning if the plugin omits a fallback.
Scheduling fails without replacing the prior schedule if the primary or weekday requests do not fit.

### Kill warning

`setKillWarning(title, body)` stores a warning message. If the app is backgrounded while an alarm is
ringing, the plugin posts a non-actionable notification warning the user not to force-quit the app.
`clearKillWarning()` removes the stored message; the pending notification is auto-dismissed when the
app returns to the foreground.
While a warning is configured, alarm scheduling reserves one of the 64 pending-request slots.
Enabling the warning fails if no slot is available for that reservation.

### Events emitted

iOS emits a subset of the full event hierarchy — only events that are achievable within the
notification delivery model:

- `WarmAlarmScheduled`
- `WarmAlarmFired`
- `WarmAlarmStopped`
- `WarmAlarmSnoozed`
- `WarmAlarmFailed`

Wake-check events (`WarmAlarmWakeCheckShown`, `WarmAlarmWakeCheckDismissed`,
`WarmAlarmWakeCheckExpired`, `WarmAlarmRetriggered`) are not emitted on iOS.

---

## Pigeon wire layer

All Dart ↔ Swift communication is generated by [Pigeon][pigeon_link]. The schema lives in
`pigeons/messages.dart`; generated outputs (`Messages.g.swift`, `lib/src/messages.g.dart`) are
never hand-edited. Run `melos run generate` after any schema change.

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
