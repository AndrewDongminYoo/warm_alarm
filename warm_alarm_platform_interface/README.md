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
The default instance is `MethodChannelWarmAlarm`, which throws `UnimplementedError` for all methods
and serves as a build-time guard.

**Contract methods:**

| Method                       | Returns                    | Description                                            |
| ---------------------------- | -------------------------- | ------------------------------------------------------ |
| `getCapabilities()`          | `WarmAlarmCapabilities`    | Per-feature support status for this platform           |
| `getPermissionState()`       | `WarmAlarmPermissionState` | Current notification and exact-alarm permission grants |
| `getReadiness()`             | `WarmAlarmReadiness`       | Aggregated readiness level with reason codes           |
| `scheduleAlarm(schedule)`    | `WarmAlarmScheduleResult`  | Schedule an alarm and return its assigned ID           |
| `cancelAlarm(id)`            | `Future<void>`             | Cancel a specific alarm by ID                          |
| `cancelAllAlarms()`          | `Future<void>`             | Cancel all scheduled alarms                            |
| `getScheduledAlarms()`       | `List<WarmAlarmSnapshot>`  | Enumerate all currently scheduled alarms               |
| `isRinging({id})`            | `Future<bool>`             | Whether an alarm (or any alarm) is ringing             |
| `setKillWarning(title,body)` | `Future<void>`             | Post a persistent kill-warning notification            |
| `clearKillWarning()`         | `Future<void>`             | Dismiss the kill-warning notification                  |
| `events`                     | `Stream<WarmAlarmEvent>`   | Broadcast stream of alarm lifecycle events             |

### Public models

All public-facing model classes live in `lib/src/models/` and are stable across platform
implementations. Pigeon-generated wire DTOs (in `lib/src/messages.g.dart` of each platform package)
are never exposed here.

| Model                      | Purpose                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------- |
| `WarmAlarmSchedule`        | Full alarm configuration passed to `scheduleAlarm()`                                              |
| `WarmAlarmAudio`           | Audio source, looping, volume, fade-in curve, and vibration settings                              |
| `WarmAlarmNotification`    | Notification title, body, action button labels, and Android-specific icon/color                   |
| `WarmAlarmSnooze`          | Snooze duration                                                                                   |
| `WarmAlarmRecurrence`      | Weekly recurrence via a weekday bitmask (Mon = 1, Tue = 2, … Sun = 64)                            |
| `WarmAlarmWakeCheck`       | Wake-check configuration: check delay, optional retrigger delay, and max retrigger count          |
| `WarmAlarmSnapshot`        | Lightweight read-back of a scheduled alarm                                                        |
| `WarmAlarmCapabilities`    | Per-feature `WarmAlarmSupportStatus`: exact scheduling, background audio, full-screen, wake-check |
| `WarmAlarmPermissionState` | Runtime permission grant flags                                                                    |
| `WarmAlarmReadiness`       | Aggregated readiness level plus a list of actionable `WarmAlarmReadinessReason` codes             |
| `WarmAlarmScheduleResult`  | Schedule outcome: `alarmId`, `readiness` snapshot, optional `WarmAlarmWarning`                    |
| `WarmAlarmEvent`           | Sealed class hierarchy covering every alarm lifecycle transition                                  |
| `WarmAlarmVolumeFadeStep`  | A single (time, volume) breakpoint in a custom fade curve                                         |

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
