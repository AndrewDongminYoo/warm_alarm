# warm_alarm

[![CI][ci_badge]][ci_link]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

A platform-honest alarm plugin for Flutter — schedules reliable alarms on Android, iOS, and macOS
with a capability/permission/readiness model that tells you exactly what the current platform can
deliver before you commit to a schedule.

---

## Background

`warm_alarm` was extracted from the core alarm functionality of [WarmWake][warmwake_link].
It is maintained as an independent Flutter plugin and does not require the WarmWake app.

---

## Features

- **Capability-first design** — each platform reports exactly what it can do; no silent no-ops
- **Three-level system inspection** — `getCapabilities()`, `getPermissionState()`, and `getReadiness()` before you schedule
- **Reactive event stream** — sealed `WarmAlarmEvent` types covering every alarm lifecycle transition
- **Custom audio** — local file, asset, or platform default with optional fade-in, looping, and vibration
- **Wake-check flow** (Android only) — verifies the user is awake after dismissal and retriggers if not
- **Snooze and recurrence** — built-in snooze duration and weekly recurrence by weekday
- **Federated plugin** — independent implementations for Android, iOS, and macOS

---

## Installation

Add `warm_alarm` to your Flutter app.

```yaml
dependencies:
  warm_alarm: ^0.1.1
```

Then run:

```bash
flutter pub get
```

---

## Quick Start

```dart
import 'package:warm_alarm/warm_alarm.dart';

// 1. Check whether the platform can deliver a reliable alarm.
final readiness = await WarmAlarm.getReadiness();
if (readiness.level == WarmAlarmReadinessLevel.blocked) {
  // Surface readiness.reasons to the user so they can fix permissions.
  return;
}

// 2. Schedule an alarm with audio, snooze, and a wake-check follow-up.
final result = await WarmAlarm.scheduleAlarm(
  WarmAlarmSchedule(
    id: 1,
    scheduledAt: DateTime.now().add(const Duration(minutes: 30)),
    notification: const WarmAlarmNotification(
      title: 'Wake up!',
      body: 'Good morning',
      stopActionTitle: 'Stop',
      snoozeActionTitle: 'Snooze',
    ),
    audio: const WarmAlarmAudio(loop: true, vibrate: true),
    snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
    wakeCheck: const WarmAlarmWakeCheck(
      checkDelay: Duration(minutes: 2),
      retriggerDelay: Duration(minutes: 1),
    ),
  ),
);
print('Scheduled alarm ${result.alarmId}, readiness: ${result.readiness.level}');

// 3. React to alarm lifecycle events.
WarmAlarm.events.listen((event) {
  switch (event) {
    case WarmAlarmFired():   print('Alarm ${event.alarmId} fired');
    case WarmAlarmStopped(): print('Alarm ${event.alarmId} stopped');
    case WarmAlarmSnoozed(): print('Snoozed for ${event.duration}');
    default: break;
  }
});

// 4. Cancel an alarm.
await WarmAlarm.cancelAlarm(1);
```

---

## Platform Capabilities

| Feature                   | Android    | iOS        | macOS      |
| ------------------------- | ---------- | ---------- | ---------- |
| Notification scheduling   | ✅ Full    | ✅ Full    | ✅ Full    |
| Exact alarm scheduling    | ✅ Full    | ⚠️ Limited | ⚠️ Limited |
| Background audio playback | ⚠️ Limited | ⚠️ Limited | ⚠️ Limited |
| Full-screen presentation  | ✅ Full    | ❌ None    | ❌ None    |
| Wake-check                | ✅ Full    | ❌ None    | ❌ None    |

**⚠️ Limited** means the native implementation reports conditional support. Call `getReadiness()` before you schedule an alarm.

Call `getReadiness()` at runtime and surface the `reasons` list to your users so they can take
corrective action (grant permissions, disable battery optimization, etc.).

---

## API Reference

### `WarmAlarm` — static entry point

| Method                    | Returns                      | Description                                                 |
| ------------------------- | ---------------------------- | ----------------------------------------------------------- |
| `init()`                  | `Future<void>`               | Rehydrate native alarm state after a process restart        |
| `getCapabilities()`       | `WarmAlarmCapabilities`      | Per-feature support status for the current platform         |
| `getPermissionState()`    | `WarmAlarmPermissionState`   | Current notification and exact-alarm permission grants      |
| `getReadiness()`          | `WarmAlarmReadiness`         | Overall system readiness with actionable reason codes       |
| `scheduleAlarm(schedule)` | `WarmAlarmScheduleResult`    | Schedule an alarm; returns the assigned ID and any warnings |
| `cancelAlarm(id)`         | `Future<void>`               | Cancel a specific alarm by ID                               |
| `cancelAllAlarms()`       | `Future<void>`               | Cancel all scheduled alarms                                 |
| `getScheduledAlarms()`    | `List<WarmAlarmSnapshot>`    | List all currently scheduled alarms                         |
| `hasAlarm()`              | `Future<bool>`               | Whether any future alarm is currently scheduled             |
| `getAlarm(id)`            | `Future<WarmAlarmSnapshot?>` | Fetch a single future scheduled alarm by ID                 |
| `isRinging({id})`         | `Future<bool>`               | Whether an alarm (or any alarm) is currently ringing        |
| `setKillWarning(...)`     | `Future<void>`               | Post a persistent notification warning against force-quit   |
| `clearKillWarning()`      | `Future<void>`               | Remove the kill-warning notification                        |
| `events`                  | `Stream<WarmAlarmEvent>`     | Real-time alarm lifecycle event stream                      |

### Key data classes

| Class                      | Purpose                                                                                                                          |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `WarmAlarmSchedule`        | Full alarm configuration: timing, notification, audio, snooze, recurrence, payload, wake-check                                   |
| `WarmAlarmCapabilities`    | `WarmAlarmSupportStatus` per feature: notification & exact scheduling, background audio, full-screen, wake-check, Live Activity  |
| `WarmAlarmReadiness`       | `level` (`ready \| limited \| blocked \| unsupported`) + `List<WarmAlarmReadinessReason>`                                        |
| `WarmAlarmPermissionState` | Boolean flags: `notificationsGranted`, `exactAlarmGranted`, `fullScreenIntentGranted`                                            |
| `WarmAlarmScheduleResult`  | `alarmId`, `readiness`, optional `WarmAlarmWarning`                                                                              |
| `WarmAlarmAudio`           | `filePath?`, `assetPath?`, `loop`, `volume?`, `fadeInDuration?`, `fadeSteps?`, `volumeEnforced`, `vibrate`                       |
| `WarmAlarmNotification`    | `title`, `body`, `stopActionTitle?`, `snoozeActionTitle?`, `androidIcon?`, `androidIconColor?`, `keepNotificationAfterAlarmEnds` |
| `WarmAlarmSnooze`          | `duration`                                                                                                                       |
| `WarmAlarmRecurrence`      | `weekdays` — list of ISO weekday numbers (1 = Monday … 7 = Sunday)                                                               |
| `WarmAlarmWakeCheck`       | `checkDelay`, `retriggerDelay?`, `maxRetriggers` (Android only)                                                                  |
| `WarmAlarmVolumeFadeStep`  | `time` (offset from alarm start), `volume` (0.0–1.0) — element of `WarmAlarmAudio.fadeSteps`                                     |
| `WarmAlarmSnapshot`        | Full scheduled-alarm record returned by `getScheduledAlarms()` — mirrors `WarmAlarmSchedule` fields                              |

### `WarmAlarmEvent` — sealed event types

| Subtype                       | Payload                                         |
| ----------------------------- | ----------------------------------------------- |
| `WarmAlarmScheduled`          | `alarmId`, `occurredAt`                         |
| `WarmAlarmFired`              | `alarmId`, `occurredAt`, `payload?`             |
| `WarmAlarmStopped`            | `alarmId`, `occurredAt`, `payload?`             |
| `WarmAlarmSnoozed`            | `alarmId`, `occurredAt`, `duration`, `payload?` |
| `WarmAlarmFailed`             | `alarmId`, `occurredAt`, `WarmAlarmFailure`     |
| `WarmAlarmWakeCheckShown`     | `alarmId`, `occurredAt` (Android)               |
| `WarmAlarmWakeCheckDismissed` | `alarmId`, `occurredAt` (Android)               |
| `WarmAlarmWakeCheckExpired`   | `alarmId`, `occurredAt` (Android)               |
| `WarmAlarmRetriggered`        | `alarmId`, `occurredAt`, `payload?` (Android)   |

---

## Migrating from `alarm`

`warm_alarm` is a drop-in design replacement for the [`alarm`][alarm_package_link] package,
with a richer capability model, macOS support, and a cleaner public/wire boundary.

### Why switch?

| Concern                | `alarm`                                    | `warm_alarm`                                                                                 |
| ---------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------- |
| Platform coverage      | Android + iOS                              | Android + iOS + **macOS**                                                                    |
| Pre-schedule diagnosis | None — silent failures                     | `getCapabilities()` + `getPermissionState()` + `getReadiness()` with actionable reason codes |
| Schedule result        | `bool` success flag                        | `WarmAlarmScheduleResult` — includes readiness level and optional warning message            |
| Wake verification      | None                                       | `WarmAlarmWakeCheck` — detects if the user actually woke up; retriggers the alarm if not     |
| Snooze                 | App-layer only                             | Built-in `WarmAlarmSnooze`; notification action handled natively                             |
| Event model            | `ringStream` / `updateStream` (deprecated) | `Stream<WarmAlarmEvent>` — 9 typed events in a sealed class hierarchy                        |
| Store location         | Dart-side `SharedPreferences`              | Native (`SharedPreferences` / `UserDefaults`) — survives Flutter engine restarts             |
| Snapshot richness      | Full `AlarmSettings` from Dart store       | Full `WarmAlarmSnapshot` reconstructed from native store via `getScheduledAlarms()`          |
| Pigeon boundary        | Single shared schema for all platforms     | Per-platform schema — iOS and Android can diverge safely                                     |

### API mapping

| `alarm`                              | `warm_alarm`                                                                 | Notes                                                     |
| ------------------------------------ | ---------------------------------------------------------------------------- | --------------------------------------------------------- |
| `Alarm.set(alarmSettings:)`          | `WarmAlarm.scheduleAlarm(schedule)`                                          | Returns `WarmAlarmScheduleResult` instead of `bool`       |
| `Alarm.stop(id)`                     | `WarmAlarm.cancelAlarm(id)`                                                  |                                                           |
| `Alarm.stopAll()`                    | `WarmAlarm.cancelAllAlarms()`                                                |                                                           |
| `Alarm.getAlarms()`                  | `WarmAlarm.getScheduledAlarms()`                                             | Returns full `WarmAlarmSnapshot` list                     |
| `Alarm.isRinging([id])`              | `WarmAlarm.isRinging(id: id)`                                                |                                                           |
| `Alarm.setWarningNotificationOnKill` | `WarmAlarm.setKillWarning(title:body:)`                                      | Paired with `clearKillWarning()`                          |
| `Alarm.scheduled` / `Alarm.ringing`  | `WarmAlarm.events`                                                           | Build a `StateNotifier`/`Bloc` on top of the event stream |
| `AlarmSettings.volumeSettings`       | `WarmAlarmAudio` (`volume`, `fadeInDuration`, `fadeSteps`, `volumeEnforced`) |                                                           |
| `NotificationSettings.icon`          | `WarmAlarmNotification.androidIcon`                                          | Android only                                              |
| `NotificationSettings.iconColor`     | `WarmAlarmNotification.androidIconColor`                                     | Android only — ARGB int instead of `Color`                |
| `AlarmSettings.payload`              | `WarmAlarmSchedule.payload`                                                  | Propagated to every event type                            |

---

## License

BSD-3-Clause — Copyright (c) 2026, Dongmin Yu. See [LICENSE](LICENSE) for details.

<!-- links -->

[ci_badge]: https://github.com/AndrewDongminYoo/warm_alarm/actions/workflows/warm_alarm.yaml/badge.svg
[ci_link]: https://github.com/AndrewDongminYoo/warm_alarm/actions/workflows/warm_alarm.yaml
[license_badge]: https://img.shields.io/badge/license-BSD--3--Clause-blue.svg
[license_link]: https://opensource.org/licenses/BSD-3-Clause
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[alarm_package_link]: https://pub.dev/packages/alarm
[warmwake_link]: https://warmwake.donminzzi.kr
