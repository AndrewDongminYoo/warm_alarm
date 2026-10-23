# warm_alarm

> A platform-honest alarm plugin for Flutter

[![CI][ci_badge]][ci_link]
![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

---

## Features

For example usage, testing boundaries, and project decisions, see the [documentation guide](docs/README.md).

- **Durable lifecycle events** — bounded native replay when the Dart engine reconnects.
- **Opt-in iOS Live Activities** — host-provided widgets with explicit start, update, and end operations.
- **Capability-first design** — feature support is reported at runtime, with platform-specific limits documented below
- **Three-level system inspection** — `getCapabilities()`, `getPermissionState()`, and `getReadiness()` before you schedule
- **Reactive event stream** — sealed `WarmAlarmEvent` types for every alarm lifecycle transition
- **Custom audio** — local file, asset, or platform default with fade steps, looping, and platform-specific vibration control
- **Wake-check flow** (Android) — verifies the user is actually awake after dismissal and retriggers when they are not
- **Snooze and recurrence** — built-in snooze duration and weekly recurrence by weekday
- **Federated plugin** — independent implementations for Android, iOS, and macOS

---

## Installation

Add `warm_alarm` to your Flutter app.

```yaml
dependencies:
  warm_alarm: ^0.1.9
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
for (final warning in result.warnings) {
  print('Warning (${warning.code?.name ?? 'unclassified'}): ${warning.message}');
}

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

| Feature                   | Android        | iOS                     | macOS          |
| ------------------------- | -------------- | ----------------------- | -------------- |
| Notification scheduling   | ✅ Full        | ✅ Full                 | ✅ Full        |
| Exact alarm scheduling    | ✅ Full        | ✅ or ⚠️                | ❌ Unsupported |
| Background audio playback | ⚠️ Limited     | ⚠️ Limited              | ⚠️ Limited     |
| Full-screen presentation  | ✅ Full        | ❌ Unsupported          | ❌ Unsupported |
| Wake-check                | ✅ Full        | ❌ Unsupported          | ❌ Unsupported |
| Custom Live Activities    | ❌ Unsupported | Opt-in host integration | ❌ Unsupported |

**⚠️ Limited** means the native implementation reports conditional support.
Capabilities are runtime snapshots: iOS exact scheduling also depends on host configuration and AlarmKit authorization.
Call `getReadiness()` before scheduling; neither a supported capability nor a ready snapshot guarantees future alarm delivery.

See the [audio contract and durable event delivery](warm_alarm/README.md) for source precedence, platform limits, validation, and replay semantics.
Custom Live Activities require the [iOS host adapter and Widget Extension](warm_alarm_ios/example/live_activity/README.md).

Call `getReadiness()` at runtime and surface the reasons to your users so they can address the permissions or platform limits that were detected.
Not every reason has a settings action, and granting notification permission does not remove the background-execution limit of Apple's User Notifications backend.

### iOS 26 AlarmKit setup

Add a non-empty `NSAlarmKitUsageDescription` to the host app's `Info.plist` to opt in to AlarmKit on iOS 26 or later.
The first native schedule can show the AlarmKit authorization prompt.
The plugin falls back to User Notifications when AlarmKit is unavailable, unconfigured, denied, or fails to schedule and native cleanup succeeds.
It returns an error instead of installing a second backend when native cleanup cannot be confirmed.
`getCapabilities()` reports exact scheduling as `supported` only when the runtime and host configuration allow the AlarmKit backend.
The system AlarmKit UI does not open an arbitrary Flutter full-screen route.

AlarmKit Snooze uses a post-alert countdown.
Apple requires a Widget Extension with an `ActivityConfiguration` for `AlarmAttributes<Never>` when the host enables this countdown.
Declare `extension Never: @retroactive AlarmMetadata {}` in the extension so it uses the same module-independent empty metadata type as the plugin.
Set both `NSSupportsLiveActivities` and `WarmAlarmAlarmKitLiveActivityEnabled` to `true` in the app target's `Info.plist` only after the extension is ready.
Until then, schedules with Snooze use the User Notifications fallback and return a warning.
See the [`warm_alarm_ios` host requirements][warm_alarm_ios_requirements] for the complete value mapping and event limitations.

---

## API Reference

### `WarmAlarm` — static entry point

| Method                            | Returns                               | Description                                                 |
| --------------------------------- | ------------------------------------- | ----------------------------------------------------------- |
| `init()`                          | `Future<void>`                        | Rehydrate native alarm state after a process restart        |
| `startLiveActivity(state)`        | `Future<WarmAlarmLiveActivityResult>` | Start a custom activity on a configured iOS host            |
| `updateLiveActivity(id, state)`   | `Future<WarmAlarmLiveActivityResult>` | Update activity content without rescheduling the alarm      |
| `endLiveActivity(id)`             | `Future<WarmAlarmLiveActivityResult>` | End a custom activity by its identifier                     |
| `prepareSystemSound(...)`         | `Future<String?>`                     | Prepare an AlarmKit sound; return null if unsupported       |
| `getCapabilities()`               | `Future<WarmAlarmCapabilities>`       | Per-feature support status for the current platform         |
| `getPermissionState()`            | `Future<WarmAlarmPermissionState>`    | Current notification and exact-alarm permission grants      |
| `getReadiness()`                  | `Future<WarmAlarmReadiness>`          | Overall system readiness with actionable reason codes       |
| `requestNotificationPermission()` | `Future<WarmAlarmRemediationResult>`  | Request notification authorization and return current state |
| `openReadinessSettings(reason)`   | `Future<WarmAlarmRemediationResult>`  | Open supported native settings and return current state     |
| `scheduleAlarm(schedule)`         | `Future<WarmAlarmScheduleResult>`     | Schedule an alarm; returns the assigned ID and any warnings |
| `cancelAlarm(id)`                 | `Future<void>`                        | Cancel a specific alarm by ID                               |
| `cancelAllAlarms()`               | `Future<void>`                        | Cancel all scheduled alarms                                 |
| `getScheduledAlarms()`            | `Future<List<WarmAlarmSnapshot>>`     | List all currently scheduled alarms                         |
| `hasAlarm()`                      | `Future<bool>`                        | Whether any future alarm is currently scheduled             |
| `getAlarm(id)`                    | `Future<WarmAlarmSnapshot?>`          | Fetch a single future scheduled alarm by ID                 |
| `isRinging({id})`                 | `Future<bool>`                        | Whether an alarm (or any alarm) is currently ringing        |
| `setKillWarning(...)`             | `Future<void>`                        | Configure app-termination warning text                      |
| `clearKillWarning()`              | `Future<void>`                        | Clear the configured warning text                           |
| `events`                          | `Stream<WarmAlarmEvent>`              | Real-time alarm lifecycle event stream                      |

Warning lists require platform interface 0.1.8 or later.
Facade 0.1.9 requires platform interface 0.1.8 and the published Android 0.1.6, iOS 0.1.13, and macOS 0.1.8 implementations that populate the list.
On those Apple versions, scheduling with `wakeCheck` places `WarmAlarmWarningCode.unsupportedWakeCheck` first and keeps native warnings as separate entries.
The legacy `warning` getter returns that first entry or null; earlier Apple versions combine wake-check and native messages into one warning.
Other native warnings can have a null code.
Warnings do not cover every ignored option; see the [audio contract](warm_alarm/README.md#audio-contract) for reserved fields and platform-specific behavior.

`openReadinessSettings(reason)` hands the user off to a system screen and returns as soon as the
platform accepts the request, so its snapshot describes the state before the remediation — call
`getReadiness()` again once the app resumes to see the outcome.
`requestNotificationPermission()` awaits the system dialog, so its snapshot already reflects the
user's answer.

### Scheduling validation

Invalid input makes `WarmAlarm.scheduleAlarm()` complete with `ArgumentError`.

The facade validates input before it calls a platform.

- A one-time `scheduledAt` must be strictly future at millisecond precision.
- A recurrence must contain at least one ISO weekday from `1` through `7`.
- `wakeCheck.maxRetriggers` must not be negative.
- Fade-step timestamps must be strictly increasing at millisecond precision.
- Configured snooze, fade-in, fade-step, and wake-check durations must not be negative.
- Audio and fade-step volumes must be finite values from `0.0` through `1.0`.

Zero-duration fields remain valid.
A recurring schedule may use a past `scheduledAt` anchor because its next local weekday and time determine its next occurrence.

### Key data classes

| Class                           | Purpose                                                                                                                                                                                |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WarmAlarmSchedule`             | `id`, `scheduledAt`, `notification`, `audio`, `recurrence?`, `snooze?`, `wakeCheck?`, `payload?`, `androidFullScreenIntent` (default `true`)                                           |
| `WarmAlarmCapabilities`         | `WarmAlarmSupportStatus` for notification scheduling, exact scheduling, background audio, full-screen intents, wake-check, and Live Activity                                           |
| `WarmAlarmReadiness`            | `level`, `reasons`, and optional `notificationSettings`                                                                                                                                |
| `WarmAlarmNotificationSettings` | `authorizationStatus`, `alertsEnabled`, `soundsEnabled`, and nullable `timeSensitiveEnabled`                                                                                           |
| `WarmAlarmPermissionState`      | `notificationsGranted`, `exactAlarmGranted`, `fullScreenIntentGranted`                                                                                                                 |
| `WarmAlarmRemediationResult`    | `status`, `permissionState`, `readiness`                                                                                                                                               |
| `WarmAlarmScheduleResult`       | `alarmId`, `readiness`, read-only `warnings`, and `warning` (first entry or null)                                                                                                      |
| `WarmAlarmWarning`              | `message`, optional `code`; a null code still represents a warning                                                                                                                     |
| `WarmAlarmFailure`              | `code`, optional `message`                                                                                                                                                             |
| `WarmAlarmAudio`                | `filePath?`, `assetPath?`, `systemSoundFilePath?`, `loop` (default `true`), `volume?`, `fadeInDuration?`, `fadeSteps?`, `volumeEnforced` (default `false`), `vibrate` (default `true`) |
| `WarmAlarmNotification`         | `title`, `body`, `stopActionTitle?`, `snoozeActionTitle?`, `androidIcon?`, `androidIconColor?`, `keepNotificationAfterAlarmEnds` (default `false`)                                     |
| `WarmAlarmSnooze`               | `duration`                                                                                                                                                                             |
| `WarmAlarmRecurrence`           | `weekdays`: ISO weekday numbers from 1 (Monday) through 7 (Sunday)                                                                                                                     |
| `WarmAlarmWakeCheck`            | `checkDelay`, `retriggerDelay?`, `maxRetriggers?` (default `1`, Android only)                                                                                                          |
| `WarmAlarmVolumeFadeStep`       | `time` (offset from alarm start), `volume` (0.0–1.0)                                                                                                                                   |
| `WarmAlarmSnapshot`             | Schedule fields plus `systemManagedAudio` (default `false`), which reports actual system playback ownership                                                                            |
| `WarmAlarmLiveActivityState`    | `alarmId`, `title`, `status`, optional `scheduledAt`; content for a host-provided widget, not an alarm schedule                                                                        |
| `WarmAlarmLiveActivityResult`   | `status`, optional `activityId`                                                                                                                                                        |

### `WarmAlarmEvent` — sealed event types

| Subtype                       | Payload                                                 |
| ----------------------------- | ------------------------------------------------------- |
| `WarmAlarmScheduled`          | `alarmId`, `occurredAt`                                 |
| `WarmAlarmFired`              | `alarmId`, `occurredAt`, `payload?`                     |
| `WarmAlarmStopped`            | `alarmId`, `occurredAt`, `payload?`                     |
| `WarmAlarmSnoozed`            | `alarmId`, `occurredAt`, `duration`, `payload?`         |
| `WarmAlarmFailed`             | `alarmId`, `occurredAt`, `failure` (`WarmAlarmFailure`) |
| `WarmAlarmWakeCheckShown`     | `alarmId`, `occurredAt` (Android)                       |
| `WarmAlarmWakeCheckDismissed` | `alarmId`, `occurredAt` (Android)                       |
| `WarmAlarmWakeCheckExpired`   | `alarmId`, `occurredAt` (Android)                       |
| `WarmAlarmRetriggered`        | `alarmId`, `occurredAt`, `payload?` (Android)           |

### Enums

**`WarmAlarmSupportStatus`**: `supported`, `limited`, `unsupported`, `unknown`

**`WarmAlarmReadinessLevel`**: `ready`, `limited`, `blocked`, `unsupported`

**`WarmAlarmReadinessReason`**: `notificationPermissionDenied`, `exactAlarmPermissionDenied`, `fullScreenPermissionDenied`, `backgroundExecutionLimited`, `backgroundAudioLimited`, `platformUnsupported`, `batteryOptimizationMayDelay`, `unknown`

**`WarmAlarmRemediationStatus`**: `completed`, `unavailable`, `unsupported`

**`WarmAlarmFailureCode`**: `unknown`, `invalidArguments`, `permissionDenied`, `exactAlarmUnavailable`, `notificationUnavailable`, `audioFileNotFound`, `audioPlaybackFailed`, `schedulingFailed`, `platformInternalError`

**`WarmAlarmNotificationAuthorizationStatus`**: `notDetermined`, `denied`, `authorized`, `provisional`, `ephemeral`, `unknown`

**`WarmAlarmWarningCode`**: `unsupportedWakeCheck`, `unsupportedFadeIn`

**`WarmAlarmLiveActivityStatus`**: `scheduled`, `ringing`, `snoozed`

**`WarmAlarmLiveActivityResultStatus`**: `completed`, `unsupported`, `disabled`, `notFound`

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

| Phase | Scope                                                                                                                      | Status  |
| ----- | -------------------------------------------------------------------------------------------------------------------------- | ------- |
| 1A    | Core Dart API, platform interface, Android AlarmManager + ForegroundService                                                | ✅ Done |
| 1B    | Android audio (MediaPlayer), snooze, recurrence, notification actions                                                      | ✅ Done |
| 1C    | iOS + macOS (UNUserNotificationCenter + AVAudioPlayer), kill-warning lifecycle                                             | ✅ Done |
| 2     | Android wake-check: retrigger flow, `WarmAlarmWakeCheck`, `WarmAlarmBootReceiver` stub                                     | ✅ Done |
| 3     | Parity with `alarm`: `isRinging`, `payload`, enriched snapshot, staircase volume fade, notification icon, kill-warning API | ✅ Done |
| 4     | App-start recovery (`init()`), convenience query (`hasAlarm`, `getAlarm`), `androidFullScreenIntent` toggle                | ✅ Done |

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
[warm_alarm_ios_requirements]: https://github.com/AndrewDongminYoo/warm_alarm/tree/main/warm_alarm_ios#alarmkit-opt-in
