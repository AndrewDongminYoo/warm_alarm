# warm_alarm_platform_interface

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

The common platform interface for the [`warm_alarm`][warm_alarm_link] plugin. This package defines
the abstract contract that all platform implementations must satisfy, and houses all hand-written
public model classes shared across platforms.

---

## What's in this package

### `WarmAlarmPlatform` — abstract contract

The abstract class that every platform implementation extends. Platform plugins call
`WarmAlarmPlatform.instance = MyPlatformImpl()` in their `registerWith()` to install themselves.
The default instance is `MethodChannelWarmAlarm`, a no-op fallback for apps without a registered platform implementation.
It reports unknown capabilities, unsupported readiness, false permission/ringing flags, and empty scheduled-alarm and event collections.
Its scheduling result has alarm ID `0` and unsupported readiness; it does not schedule a native alarm.

**Contract methods:**

`prepareSystemSound(primaryFilePath: ..., backgroundAssetPath: ...)` returns a complete system sound path on supported implementations, or null on existing backends.
Pass that path through `WarmAlarmAudio.systemSoundFilePath` while retaining the normal `filePath` and `assetPath` for fallback.
Only `WarmAlarmSnapshot.systemManagedAudio` identifies actual system playback ownership; its default is false.
Apps must wait for the snapshot before starting a second player.

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
| `isRinging({id})`                 | `Future<bool>`                        | Whether an alarm (or any alarm) is currently ringing        |
| `setKillWarning(...)`             | `Future<void>`                        | Configure app-termination warning text                      |
| `clearKillWarning()`              | `Future<void>`                        | Clear the configured warning text                           |
| `events`                          | `Stream<WarmAlarmEvent>`              | Real-time alarm lifecycle event stream                      |

The two remediation methods carry an `unsupported` default, so a platform package built against an
earlier version of this contract keeps working and simply reports that it cannot remediate.
The endorsed Android, iOS, and macOS implementations override those remediation defaults.
Live Activity methods also have inherited `unsupported` defaults, and `prepareSystemSound()` defaults to null.
The iOS implementation provides these optional integrations when its host and operating system support them.
`openReadinessSettings()` hands the user off to a separate screen and returns as soon as the
platform accepts the request, so its snapshot describes the state before the user acted on it — call
`getReadiness()` again after the app resumes.
`requestNotificationPermission()` awaits the system dialog, so its snapshot is the state after the
user answered.

### Public models

All public-facing model classes live in `lib/src/models/` and are stable across platform
implementations. Pigeon-generated wire DTOs (in `lib/src/messages.g.dart` of each platform package)
are never exposed here.

| Model                           | Purpose                                                                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `WarmAlarmSchedule`             | Full alarm configuration passed to `scheduleAlarm()`                                                                            |
| `WarmAlarmAudio`                | Audio source, looping, volume, fade-in curve, and vibration settings                                                            |
| `WarmAlarmNotification`         | Notification title, body, action button labels, and Android-specific icon/color                                                 |
| `WarmAlarmSnooze`               | Snooze duration                                                                                                                 |
| `WarmAlarmRecurrence`           | Weekly recurrence via a list of ISO weekday numbers (`weekdays`, 1 = Monday … 7 = Sunday)                                       |
| `WarmAlarmWakeCheck`            | Wake-check configuration: check delay, optional retrigger delay, and max retrigger count                                        |
| `WarmAlarmSnapshot`             | Scheduled-alarm fields plus `systemManagedAudio` (default `false`)                                                              |
| `WarmAlarmCapabilities`         | Per-feature `WarmAlarmSupportStatus`: notification & exact scheduling, background audio, full-screen, wake-check, Live Activity |
| `WarmAlarmPermissionState`      | Runtime permission grant flags                                                                                                  |
| `WarmAlarmReadiness`            | Aggregated readiness level plus a list of actionable `WarmAlarmReadinessReason` codes                                           |
| `WarmAlarmRemediationResult`    | Action status plus permission and readiness state when the action returns                                                       |
| `WarmAlarmScheduleResult`       | Schedule outcome: `alarmId`, `readiness` snapshot, `warnings` list, and `warning` (its first entry)                             |
| `WarmAlarmEvent`                | Sealed class hierarchy covering every alarm lifecycle transition                                                                |
| `WarmAlarmVolumeFadeStep`       | A single (time, volume) breakpoint in a custom fade curve                                                                       |
| `WarmAlarmNotificationSettings` | Granular notification authorization, alert, sound, and Time Sensitive settings                                                  |
| `WarmAlarmWarning`              | Scheduling message with an optional `WarmAlarmWarningCode`                                                                      |
| `WarmAlarmFailure`              | `WarmAlarmFailureCode` and an optional diagnostic message                                                                       |
| `WarmAlarmLiveActivityState`    | Host-widget content: alarm ID, title, `WarmAlarmLiveActivityStatus`, and optional next occurrence                               |
| `WarmAlarmLiveActivityResult`   | `WarmAlarmLiveActivityResultStatus` and optional ActivityKit identifier                                                         |

`WarmAlarmScheduleResult.warnings` is a read-only list in detection order.
The existing `warning` getter returns the first entry, or null when the list is empty.
Existing implementations can keep passing the single `warning` constructor argument; it becomes the only list entry.
New implementations should use `WarmAlarmScheduleResult.withWarnings(warnings: ..., alarmId: ..., readiness: ...)`.
This constructor copies the supplied list so callers can reuse their warning accumulator without changing a returned result.
The separate constructors keep the existing const-construction path and prevent combining the single-warning and list arguments.
An empty list does not guarantee that every requested option was applied.
The list API requires `warm_alarm_platform_interface` 0.1.8 or later.
Android 0.1.6, iOS 0.1.13, and macOS 0.1.8 are the first platform versions prepared to use the list constructor.
They must be published before consumers can resolve these implementations from pub.dev.
Earlier platform versions continue to return at most one entry through the legacy constructor.

---

## Implementing a new platform

1. Add `warm_alarm_platform_interface` as a dependency.
2. Extend `WarmAlarmPlatform` (do **not** implement it — extending ensures forward compatibility
   when new methods are added with default implementations).
3. Call `WarmAlarmPlatform.instance = YourImpl()` in your `static void registerWith()` method.

```dart
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarmMyPlatform extends WarmAlarmPlatform {
  static void registerWith() {
    WarmAlarmPlatform.instance = WarmAlarmMyPlatform();
  }

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async { /* ... */ }

  // ... implement remaining methods
}
```

All native ↔ Dart communication should be code-generated by [Pigeon][pigeon_link]. Keep generated
wire types in `lib/src/` (private) and map them to the public models from this package at the
Dart layer.

---

## License

BSD-3-Clause — Copyright (c) 2026, Dongmin Yu. See [LICENSE](LICENSE) for details.

<!-- links -->

[warm_alarm_link]: https://pub.dev/packages/warm_alarm
[license_badge]: https://img.shields.io/badge/license-BSD--3--Clause-blue.svg
[license_link]: https://opensource.org/licenses/BSD-3-Clause
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[pigeon_link]: https://pub.dev/packages/pigeon
