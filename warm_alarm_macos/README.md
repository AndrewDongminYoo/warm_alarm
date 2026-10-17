# warm_alarm_macos

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

The macOS implementation of [`warm_alarm`][warm_alarm_link].

This package is [endorsed][endorsed_link], which means you do **not** add it directly to your
`pubspec.yaml`. It is automatically included when you depend on `warm_alarm`.

---

## Platform capabilities

| Feature                   | Support    | Notes                                                      |
| ------------------------- | ---------- | ---------------------------------------------------------- |
| Notification scheduling   | ✅ Full    | `UNUserNotificationCenter`                                 |
| Exact alarm scheduling    | ❌ None    | Not supported; scheduling is notification-based only       |
| Background audio playback | ⚠️ Limited | `AVAudioPlayer` only; no `AVAudioSession` on macOS         |
| Full-screen presentation  | ❌ None    | macOS does not support full-screen intent notifications    |
| Wake-check                | ❌ None    | macOS cannot self-trigger background wakes after dismissal |

**⚠️ Limited** means alarms use `UNUserNotificationCenter` notifications.
The default notification sound can play on delivery, subject to system notification settings.
Custom in-app audio starts when the user clicks the notification or when the app receives it in the foreground.
macOS has no `AVAudioSession` category override, so the plugin does not control system audio policy.

---

## Native implementation

### Scheduling

Alarms are scheduled as `UNNotificationRequest` objects via `UNUserNotificationCenter`, using a
`UNCalendarNotificationTrigger` for the configured `scheduledAt` time.

Replacing an alarm snapshots its previous saved schedule and pending notification requests.
If registration fails, the plugin removes partial replacement requests and restores that snapshot before returning a `scheduling-failed` platform error and emitting `WarmAlarmFailed`.
If the system also rejects restoration, it attempts every previous request, keeps the previous saved schedule for initialization recovery, and returns `scheduling-rollback-failed` with both failure causes.
Pending rollback cannot recall notifications that already fired during the replacement attempt.
Stop, Snooze, and default taps reject notifications from a replaced schedule generation.
Retained one-shot notifications cannot change a later Snooze, and older actions cannot change the current playing occurrence.
Successful Snooze records the consumed occurrence so its retained repeating notification is ignored, while later recurring occurrences can still fire during a long Snooze.
Snooze shares the scheduling/cancellation mutation queue and saves its deadline and emits `WarmAlarmSnoozed` only after notification registration succeeds.
Registration failure retains the previous saved intent, attempts to restore any previous request with the same identifier, and emits `WarmAlarmFailed`.
If restoration also fails, the failure message includes both causes so the host can report incomplete recovery.

### Notification delegate integration

Registration preserves the previously installed `UNUserNotificationCenterDelegate` through a weak forwarding reference.
The default `WARM_ALARM` category and the plugin categories for custom action titles go only to the plugin; other notifications keep the host's foreground presentation and response callbacks.
The host controls presentation options and completion timing.
If the host does not implement an optional callback, presentation defaults to no options and responses complete immediately.
Settings callbacks also forward to the host.
Releasing a plugin instance restores the newest live previous delegate unless another integration has since replaced it.
Hosts must retain their own delegate, and integrations installed later must preserve forwarding themselves.

User Notifications honors `notification.stopActionTitle` and `notification.snoozeActionTitle`, with `Stop` and `Snooze` as defaults.
Different title pairs use distinct plugin category identifiers, so concurrently scheduled alarms retain their own labels.
Registration merges those categories with the host's existing categories before adding notification requests.
Hosts that replace notification categories later must also preserve the plugin categories.

### Audio

`WarmAlarmDelegate` plays audio with `AVAudioPlayer`. Because macOS does not expose `AVAudioSession`,
the plugin cannot guarantee audio playback when the system or app volume is muted. An optional
fade-in is applied by scheduling discrete volume steps as `DispatchWorkItem`s (via
`DispatchQueue.main.asyncAfter`), not a periodic timer.

A missing custom file or asset emits `WarmAlarmFailed` with `audioFileNotFound`; decoding or player-start failure emits `audioPlaybackFailed`.
Foreground delivery then requests the notification sound instead of suppressing it.
`WarmAlarmFired` records the accepted delivery, not proof of audible output; system settings can still silence the notification.
A default notification tap cannot replay the original system notification sound, so custom-audio failure remains observable through the failure event.
Stop and Snooze only stop a player owned by the same alarm and occurrence.
An accepted foreground delivery stops any earlier playback before it resolves its own source, so the newest alarm owns audio even when it falls back to the notification sound.
Stopping a recurring occurrence records it as consumed, so a retained notification of that occurrence can no longer snooze or replay it while later occurrences still fire.

### Recurrence

Weekly recurrence is delivered natively: one `UNCalendarNotificationTrigger(repeats: true)` is
registered per selected weekday, matching `DateComponents(weekday, hour, minute)`, keyed
`"{id}#{isoWeekday}"`. The series recurs without any re-arm and survives app termination. ISO
weekdays (1 = Mon … 7 = Sun) are mapped to Apple's Calendar weekdays (1 = Sun … 7 = Sat).
Dismissing an alarm ends only the current occurrence; `cancelAlarm(id)` removes every per-weekday
request and tears down the series.

### Kill warning

`setKillWarning(title, body)` stores the warning text without posting a notification.
When the app resigns active status while the plugin reports a ringing alarm, it submits a warning request with a one-second delay.
When macOS delivers the app-termination callback, the plugin submits an immediate warning request if an alarm is scheduled in the future or is currently ringing.
Both paths require configured warning text and use the same notification identifier.

`clearKillWarning()` removes the stored text and disables future warning requests; it does not remove an existing pending or delivered warning.
When the app becomes active again, the plugin removes only the pending warning request.
These handlers do not dismiss a warning that has already been delivered.
Notification permission and delivery of the relevant lifecycle callback are required.

### Events emitted

macOS emits the same subset of events as iOS:

- `WarmAlarmScheduled`
- `WarmAlarmFired`
- `WarmAlarmStopped`
- `WarmAlarmSnoozed`
- `WarmAlarmFailed`

Wake-check events are not supported on macOS.

Events are written to an app-scoped Application Support queue before dispatch and replayed during `WarmAlarm.init()`.
Only a successful Dart callback removes an event.
The queue retains 64 entries, drops the oldest on overflow, and discards malformed records while preserving valid neighbors.
The Dart wrapper buffers up to 64 events before the first stream listener.

### Audio limitations

Custom playback selects a nonempty file path before an asset path.
`volumeEnforced` affects only `AVAudioPlayer.volume`; it does not change or guarantee the system output volume.
`vibrate` has no macOS background-haptic equivalent.
Use `fadeSteps` for fades because `fadeInDuration` is currently a serialized hint with no playback effect.

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
