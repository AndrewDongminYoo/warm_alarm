# warm_alarm

> A platform-honest alarm plugin for Flutter

[![CI][ci_badge]][ci_link]
![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

---

## Features

- **Capability-first design** — each platform reports exactly what it can do; no silent no-ops
- **Three-level system inspection** — `getCapabilities()`, `getPermissionState()`, and `getReadiness()` before you schedule
- **Reactive event stream** — sealed `WarmAlarmEvent` types for every alarm lifecycle transition
- **Custom audio** — local file, asset, or platform default with fade-in, looping, and vibration control
- **Wake-check flow** (Android) — verifies the user is actually awake after dismissal and retriggers when they are not
- **Snooze and recurrence** — built-in snooze duration and weekly recurrence by weekday
- **Federated plugin** — independent implementations for Android, iOS, and macOS

---

## Installation

> **Note:** `warm_alarm` is not yet published to pub.dev. Add it from your local workspace or via a Git reference.

**From a local path** (monorepo or local checkout):

```yaml
dependencies:
  warm_alarm:
    path: ../warm_alarm/warm_alarm
```

**From Git:**

```yaml
dependencies:
  warm_alarm:
    git:
      url: https://github.com/AndrewDongminYoo/warm_alarm.git
      path: warm_alarm
```

Then run:

```bash
flutter pub get
```

---

## Quick Start

```dart
import 'package:warm_alarm/warm_alarm.dart';

// 1. Check whether the current platform can deliver a reliable alarm.
final readiness = await WarmAlarm.getReadiness();
if (readiness.level == WarmAlarmReadinessLevel.blocked) {
  // Surface readiness.reasons to the user so they can fix permissions.
  return;
}

// 2. Schedule an alarm with audio, snooze, and a wake-check follow-up.
final schedule = WarmAlarmSchedule(
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
);

final result = await WarmAlarm.scheduleAlarm(schedule);
print('Scheduled: alarm ${result.alarmId}, readiness: ${result.readiness.level}');

// 3. React to alarm lifecycle events.
WarmAlarm.events.listen((event) {
  switch (event) {
    case WarmAlarmFired():   print('Alarm ${event.alarmId} fired');
    case WarmAlarmStopped(): print('Alarm ${event.alarmId} stopped');
    case WarmAlarmSnoozed(): print('Snoozed for ${event.snoozeDuration}');
    default: break;
  }
});

// 4. Cancel an alarm.
await WarmAlarm.cancelAlarm(1);
```

---

## Platform Capabilities

| Feature                   | Android | iOS            | macOS          |
| ------------------------- | ------- | -------------- | -------------- |
| Notification scheduling   | ✅ Full | ✅ Full        | ✅ Full        |
| Exact alarm scheduling    | ✅ Full | ⚠️ Limited     | ❌ Unsupported |
| Background audio playback | ✅ Full | ⚠️ Limited     | ⚠️ Limited     |
| Full-screen presentation  | ✅ Full | ⚠️ Limited     | ❌ Unsupported |
| Wake-check                | ✅ Full | ❌ Unsupported | ❌ Unsupported |

**⚠️ Limited** means the platform delivers the alarm via a notification instead of a guaranteed background wake. The app may not launch automatically; the alarm fires only if the user interacts with the notification.

Call `getReadiness()` at runtime and surface the reasons to your users so they can take corrective action (grant permissions, disable battery optimization, etc.).

---

## API Reference

### `WarmAlarm` — static entry point

| Method                          | Returns                    | Description                                                 |
| ------------------------------- | -------------------------- | ----------------------------------------------------------- |
| `getCapabilities()`             | `WarmAlarmCapabilities`    | Per-feature support status for the current platform         |
| `getPermissionState()`          | `WarmAlarmPermissionState` | Current notification and exact-alarm permission grants      |
| `getReadiness()`                | `WarmAlarmReadiness`       | Overall system readiness with actionable reason codes       |
| `scheduleAlarm(schedule)`       | `WarmAlarmScheduleResult`  | Schedule an alarm; returns the assigned ID and any warnings |
| `cancelAlarm(id)`               | `Future<void>`             | Cancel a specific alarm by ID                               |
| `cancelAllAlarms()`             | `Future<void>`             | Cancel all scheduled alarms                                 |
| `getScheduledAlarms()`          | `List<WarmAlarmSnapshot>`  | List all currently scheduled alarms                         |
| `events`                        | `Stream<WarmAlarmEvent>`   | Real-time alarm lifecycle event stream                      |
| `isRinging({id})`               | `Future<bool>`             | Whether any alarm — or a specific alarm by ID — is ringing  |
| `setKillWarning({title, body})` | `Future<void>`             | Set the notification shown if the app is force-killed       |
| `clearKillWarning()`            | `Future<void>`             | Clear the app-kill warning notification                     |

### Key data classes

| Class                      | Purpose                                                                                                                                             |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WarmAlarmSchedule`        | Full alarm configuration: timing, notification, audio, snooze, recurrence, wake-check                                                               |
| `WarmAlarmCapabilities`    | `WarmAlarmSupportStatus` per feature: notification & exact scheduling, background audio, full-screen, wake-check, Live Activity                     |
| `WarmAlarmReadiness`       | `level` (`ready \| limited \| blocked \| unsupported`) + `List<WarmAlarmReadinessReason>`                                                           |
| `WarmAlarmPermissionState` | Boolean flags: `notificationsGranted`, `exactAlarmGranted`, `fullScreenIntentGranted`                                                               |
| `WarmAlarmScheduleResult`  | `alarmId`, `readiness`, optional `WarmAlarmWarning`                                                                                                 |
| `WarmAlarmAudio`           | `filePath?`, `assetPath?`, `loop`, `volume?`, `fadeInDuration?`, `fadeSteps?`, `volumeEnforced`, `vibrate`                                          |
| `WarmAlarmVolumeFadeStep`  | One staircase volume-fade keyframe: `time`, `volume`                                                                                                |
| `WarmAlarmNotification`    | `title`, `body`, `stopActionTitle?`, `snoozeActionTitle?`                                                                                           |
| `WarmAlarmSnooze`          | `duration`                                                                                                                                          |
| `WarmAlarmRecurrence`      | `weekdays` — list of ISO weekday numbers (1 = Monday … 7 = Sunday)                                                                                  |
| `WarmAlarmWakeCheck`       | `checkDelay`, `retriggerDelay?`, `maxRetriggers?`                                                                                                   |
| `WarmAlarmSnapshot`        | Scheduled-alarm record: `id`, `scheduledAt`, `notification`, `audio`, `recurrence?`, `snooze?`, `wakeCheck?`, `payload?`, `androidFullScreenIntent` |

### `WarmAlarmEvent` — sealed event types

| Subtype                       | Payload                       |
| ----------------------------- | ----------------------------- |
| `WarmAlarmScheduled`          | `alarmId`                     |
| `WarmAlarmFired`              | `alarmId`                     |
| `WarmAlarmStopped`            | `alarmId`                     |
| `WarmAlarmSnoozed`            | `alarmId`, `snoozeDuration`   |
| `WarmAlarmFailed`             | `alarmId`, `WarmAlarmFailure` |
| `WarmAlarmWakeCheckShown`     | `alarmId`                     |
| `WarmAlarmWakeCheckDismissed` | `alarmId`                     |
| `WarmAlarmWakeCheckExpired`   | `alarmId`                     |
| `WarmAlarmRetriggered`        | `alarmId`                     |

### Enums

**`WarmAlarmSupportStatus`**: `supported`, `limited`, `unsupported`, `unknown`

**`WarmAlarmReadinessLevel`**: `ready`, `limited`, `blocked`, `unsupported`

**`WarmAlarmReadinessReason`**: `notificationPermissionDenied`, `exactAlarmPermissionDenied`, `fullScreenPermissionDenied`, `backgroundExecutionLimited`, `backgroundAudioLimited`, `platformUnsupported`, `batteryOptimizationMayDelay`, `unknown`

**`WarmAlarmFailureCode`**: `unknown`, `invalidArguments`, `permissionDenied`, `exactAlarmUnavailable`, `notificationUnavailable`, `audioFileNotFound`, `audioPlaybackFailed`, `schedulingFailed`, `platformInternalError`

---

## Architecture

`warm_alarm` is a [federated Flutter plugin][federated_plugins_link] split across five packages in a [Melos][melos_link] workspace:

| Package                         | Role                                                                                  |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| `warm_alarm`                    | Public API facade (`WarmAlarm` class) and runnable example app                        |
| `warm_alarm_platform_interface` | Abstract platform contract; all hand-written public models live here                  |
| `warm_alarm_android`            | Android implementation — `AlarmManager`, `ForegroundService`, audio via `MediaPlayer` |
| `warm_alarm_ios`                | iOS implementation — `UNUserNotificationCenter`, audio via `AVAudioPlayer`            |
| `warm_alarm_macos`              | macOS implementation — `UNUserNotificationCenter`, audio via `AVAudioPlayer`          |

### Native communication

All native ↔ Dart communication is type-safe and code-generated by [Pigeon][pigeon_link]. The schema lives in `pigeons/messages.dart` in each platform package. Generated outputs (`Messages.g.kt`, `Messages.g.swift`, `lib/src/messages.g.dart`) are **never hand-edited** — run `melos run generate` after any schema change.

### Model boundary

Public-facing model classes are hand-written in `warm_alarm_platform_interface/lib/` and designed for API stability. Pigeon-generated DTO types stay in `lib/src/` (private) and are never re-exported.

---

## Implementation Status

| Phase | Scope                                                                                                                      | Status     |
| ----- | -------------------------------------------------------------------------------------------------------------------------- | ---------- |
| 1A    | Core Dart API, platform interface, Android AlarmManager + ForegroundService                                                | ✅ Done    |
| 1B    | Android audio (MediaPlayer), snooze, recurrence, notification actions                                                      | ✅ Done    |
| 1C    | iOS + macOS (UNUserNotificationCenter + AVAudioPlayer), kill-warning lifecycle                                             | ✅ Done    |
| 2     | Android wake-check: retrigger flow, `WarmAlarmWakeCheck`, `WarmAlarmBootReceiver` stub                                     | ✅ Done    |
| 3     | Parity with `alarm`: `isRinging`, `payload`, enriched snapshot, staircase volume fade, notification icon, kill-warning API | ✅ Done    |
| 4     | App-start recovery (`init()`), convenience query (`hasAlarm`, `getAlarm`), `androidFullScreenIntent` toggle                | 🔲 Planned |

See `docs/plans/` for full task lists per phase.

---

## Comparison with `alarm`

`warm_alarm` started as a replacement for the [`alarm`][alarm_package_link] pub.dev package.
The table below shows the key design differences; for an API-level migration guide see
[`warm_alarm/README.md § Migrating from alarm`](warm_alarm/README.md#migrating-from-alarm).

| Concern                    | `alarm`                               | `warm_alarm`                                                              |
| -------------------------- | ------------------------------------- | ------------------------------------------------------------------------- |
| Platform coverage          | Android + iOS                         | Android + iOS + **macOS**                                                 |
| Pre-schedule diagnosis     | None                                  | `getCapabilities` + `getPermissionState` + `getReadiness`                 |
| Wake verification          | None                                  | `WarmAlarmWakeCheck` — retriggers if user is not awake (Android)          |
| Event model                | `ringStream` / `updateStream`         | `Stream<WarmAlarmEvent>` — 9 typed sealed events                          |
| Schedule store             | Dart-side `SharedPreferences`         | Native store — survives Flutter engine restarts                           |
| Pigeon schema              | Single schema shared across platforms | Per-platform schema — Android and Apple can diverge independently         |
| Public/wire model boundary | Pigeon types leak into public API     | Strict boundary: Pigeon types are private; public models are hand-written |

---

## Development

**Resolve dependencies across all packages:**

```bash
flutter pub get
```

**Melos scripts (run from repo root):**

```bash
melos run generate    # regenerate all Pigeon platform-channel bindings
melos run test        # run unit tests across all packages
melos run test:ci     # run tests with coverage (concurrency 4)
melos run format      # format Dart code and apply dart fixes (120-col)
melos run format:ci   # check formatting without modifying files
```

**Non-Dart checks:**

```bash
trunk check           # spelling, Markdown, YAML, Kotlin linting
```

**Integration tests** (requires [`fluttium_cli`][fluttium_install] installed globally):

```bash
cd warm_alarm/example && fluttium test flows/test_readiness.yaml -d android
cd warm_alarm/example && fluttium test flows/test_readiness.yaml -d macos
```

**Commit style:** [Conventional Commits][conventional_commits_link] — `feat:`, `fix:`, `chore:`, `ci:`, `docs:`, etc.

---

## License

BSD-3-Clause — Copyright (c) 2026, Dongmin Yu. See [LICENSE](LICENSE) for details.

<!-- links -->

[ci_badge]: https://github.com/AndrewDongminYoo/warm_alarm/actions/workflows/ci.yaml/badge.svg
[ci_link]: https://github.com/AndrewDongminYoo/warm_alarm/actions/workflows/ci.yaml
[coverage_badge]: warm_alarm/coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-BSD--3--Clause-blue.svg
[license_link]: https://opensource.org/licenses/BSD-3-Clause
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[federated_plugins_link]: https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins
[melos_link]: https://melos.invertase.dev/
[pigeon_link]: https://pub.dev/packages/pigeon
[fluttium_install]: https://fluttium.dev/docs/getting-started/installing-cli
[conventional_commits_link]: https://www.conventionalcommits.org/
[alarm_package_link]: https://pub.dev/packages/alarm
