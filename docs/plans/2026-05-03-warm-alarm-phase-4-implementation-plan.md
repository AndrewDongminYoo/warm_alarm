# Phase 4: App-Start Recovery, Convenience API, and Per-Schedule Platform Flags

> **Status:** APPROVED — implementation in progress on branch `feat/phase-4`.

**Goal:** Close the remaining feature gaps between `alarm` and `warm_alarm` identified in
`docs/notes/2026-05-02-alarm-to-warm-alarm-migration-analysis.md`. Phase 3 shipped parity
features (isRinging, payload, staircase fade, notification customization, kill-warning).
Phase 4 addresses the harder structural gaps: app-start alarm recovery, convenience query
methods, and optional per-schedule Android platform flags.

**Architecture note:** Phase 4 adds `init()` to the Pigeon `WarmAlarmApi` `@HostApi` on all
three platforms. The native implementations silently re-register future alarms with the OS
scheduler without emitting any `WarmAlarmScheduled` events. Groups C1 and F1 require no new
Pigeon wire types (C1 is facade-only; F1 adds a field to the existing `WarmAlarmScheduleWire`).

---

## Scope

### In Phase 4

| Task group | Feature                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------- |
| **R**      | App-start alarm recovery — `WarmAlarm.init()` reschedules missed alarms after process restart |
| **C**      | Convenience query methods — `hasAlarm()` and `getAlarm(int id)` on `WarmAlarm` facade         |
| **F**      | `androidFullScreenIntent: bool` per-schedule toggle on `WarmAlarmSchedule`                    |

### Out of Phase 4 Scope

- `allowAlarmOverlap` per-schedule — semantics undefined (what happens when two alarms fire simultaneously?); design first
- `androidStopAlarmOnTermination` — niche flag; warm_alarm keeps the foreground service alive by default which already covers the typical case
- `iOSBackgroundAudio` — iOS/macOS report `backgroundAudioPlayback: .limited`; the platform's notification-driven model makes this a capability gap, not a per-schedule toggle
- Per-alarm `stopActionTitle`/`snoozeActionTitle` on iOS — `UNNotificationCategory` is registered once at startup; dynamic per-alarm titles would require registering a category per alarm ID, complex and fragile
- Reactive state streams (`scheduled` + `ringing` `ValueStream`) — app-layer concern; document pattern in example app

---

## New Public API

### Group R1: `WarmAlarm.init()`

```dart
class WarmAlarm {
  /// Initializes the alarm system and recovers any scheduled alarms that
  /// survived a process restart.
  ///
  /// Call once during app startup (e.g. in `main()` before `runApp()`).
  ///
  /// Behavior:
  /// - Calls into the native layer, which silently re-registers future alarms
  ///   with the OS scheduler (AlarmManager on Android; cross-checks
  ///   UNNotificationCenter pending requests on iOS/macOS).
  /// - Emits no WarmAlarmScheduled events — this is a silent recovery, not a
  ///   new scheduling action.
  /// - Past alarms are skipped; callers handle the missed-alarm case by
  ///   checking [isRinging] or listening to [events].
  static Future<void> init() => _platform.init();
}
```

**Why native (not Dart-layer `scheduleAlarm()` calls):**

Two flaws ruled out the simpler Dart-loop approach:

1. Calling `scheduleAlarm()` from `init()` would emit a spurious `WarmAlarmScheduled`
   event for every recovered alarm on every app start, breaking any listener that treats
   that event as user intent.
2. Android's force-stop clears `AlarmManager` entries but preserves the `WarmAlarmStore`.
   A Dart loop calling back through `scheduleAlarm()` still requires the Flutter engine —
   it does not help the `WarmAlarmBootReceiver` path (no engine on boot).

**Android notes:**

- `AlarmManager.setExactAndAllowWhileIdle` alarms survive process death but are
  cleared on device reboot unless `RECEIVE_BOOT_COMPLETED` is declared. Phase 4
  adds a `WarmAlarmBootReceiver` that iterates the `WarmAlarmStore` and calls
  `AlarmManager.setExactAndAllowWhileIdle` for each future alarm — no Flutter engine.
- The Pigeon `init()` call (from the running app) does the same re-registration silently.

**iOS/macOS notes:**

- `UNNotificationRequest`s survive app restarts natively. The native `init()`
  cross-checks the store entries against pending notification IDs and re-schedules
  any store entry whose notification request is missing (e.g. after an app update
  that cleared pending notifications).

### Group C1: Convenience methods (facade-only, no Pigeon changes)

```dart
class WarmAlarm {
  /// Whether any alarm is currently scheduled.
  static Future<bool> hasAlarm() async =>
      (await getScheduledAlarms()).isNotEmpty;

  /// Returns the scheduled alarm with the given [id], or `null` if not found.
  static Future<WarmAlarmSnapshot?> getAlarm(int id) async {
    final alarms = await getScheduledAlarms();
    for (final alarm in alarms) {
      if (alarm.id == id) return alarm;
    }
    return null;
  }
}
```

No platform changes required.

### Group F1: `androidFullScreenIntent` per-schedule toggle

`alarm` exposes `androidFullScreenIntent: bool` (default `true`) per alarm.
`warm_alarm` currently reports the capability but does not expose a per-schedule
toggle — every alarm fires with full-screen intent on Android.

Add to `WarmAlarmSchedule` and propagate through the Android path only:

```dart
final class WarmAlarmSchedule {
  const WarmAlarmSchedule({
    ...
    this.androidFullScreenIntent = true,  // NEW — Android only
  });

  final bool androidFullScreenIntent;
}
```

iOS/macOS ignore this field (no native concept).

---

## Task List

### Group R1: App-start alarm recovery

- [ ] **R1a** Add `@async void init()` to the Pigeon `WarmAlarmApi` `@HostApi` in all three
      platform `pigeons/messages.dart` files (Android, iOS, macOS)
- [ ] **R1b** `melos run generate` — regenerate Pigeon bindings for all three platforms
- [ ] **R1c** Add `Future<void> init()` to `WarmAlarmPlatform` abstract class (delegates to Pigeon)
- [ ] **R1d** Add `WarmAlarm.init()` to the facade (delegates to `_platform.init()`)
- [ ] **R1e** Implement `init()` in Android `WarmAlarmPlugin.kt`:
  - iterate `WarmAlarmStore`, skip past alarms, call `AlarmManager.setExactAndAllowWhileIdle`
    for each future alarm — no events emitted
- [ ] **R1f** Implement `init()` in iOS `WarmAlarmPlugin.swift`:
  - fetch pending `UNNotificationRequest` IDs; for each store entry missing a pending request,
    call `UNUserNotificationCenter.add(request:)` silently
- [ ] **R1g** Implement `init()` in macOS `WarmAlarmPlugin.swift` (same as iOS)
- [ ] **R1h** Map `init()` in each platform's Dart wrapper (delegate to the Pigeon API)
- [ ] **R1i** Add `RECEIVE_BOOT_COMPLETED` permission to Android `AndroidManifest.xml`
- [ ] **R1j** Add `WarmAlarmBootReceiver` Kotlin class: on boot, load store and reschedule all future alarms
      directly via `AlarmManager` (no Flutter engine, no events)
- [ ] **R1k** Register `WarmAlarmBootReceiver` in `AndroidManifest.xml`
- [ ] **R1l** Add tests

### Group C1: Convenience query methods

- [ ] **C1a** Add `WarmAlarm.hasAlarm()` to facade (delegates to `getScheduledAlarms().isNotEmpty`)
- [ ] **C1b** Add `WarmAlarm.getAlarm(int id)` to facade (linear search over `getScheduledAlarms()`)
- [ ] **C1c** Add tests

### Group F1: `androidFullScreenIntent` per-schedule toggle

- [ ] **F1a** Add `androidFullScreenIntent: bool` to `WarmAlarmSchedule` (default `true`)
- [ ] **F1b** Add `androidFullScreenIntent: bool` to Android `WarmAlarmScheduleWire`; iOS/macOS Pigeon schemas receive the field but ignore it
- [ ] **F1c** `melos run generate`
- [ ] **F1d** Persist `androidFullScreenIntent` in Android `WarmAlarmStore` (encode/decode)
- [ ] **F1e** Apply in `WarmAlarmForegroundService.buildNotification`: conditionally set full-screen intent `PendingIntent` and `NotificationCompat.Builder.setFullScreenIntent`
- [ ] **F1f** Map in Android Dart wrapper
- [ ] **F1g** Add tests

---

## Migration Guide Impact

After Phase 4, migrating from `alarm` requires only these steps:

| `alarm` call                         | `warm_alarm` equivalent                                     |
| ------------------------------------ | ----------------------------------------------------------- |
| `Alarm.init()`                       | `await WarmAlarm.init()`                                    |
| `Alarm.checkAlarm()`                 | Covered by `WarmAlarm.init()`                               |
| `Alarm.set(alarmSettings:)`          | `WarmAlarm.scheduleAlarm(schedule)`                         |
| `Alarm.stop(id)`                     | `WarmAlarm.cancelAlarm(id)`                                 |
| `Alarm.stopAll()`                    | `WarmAlarm.cancelAllAlarms()`                               |
| `Alarm.hasAlarm()`                   | `WarmAlarm.hasAlarm()`                                      |
| `Alarm.getAlarm(id)`                 | `WarmAlarm.getAlarm(id)`                                    |
| `Alarm.getAlarms()`                  | `WarmAlarm.getScheduledAlarms()`                            |
| `Alarm.isRinging([id])`              | `WarmAlarm.isRinging(id: id)`                               |
| `Alarm.setWarningNotificationOnKill` | `WarmAlarm.setKillWarning(title:body:)`                     |
| `Alarm.scheduled` / `Alarm.ringing`  | Build `WarmAlarmStateNotifier` on top of `WarmAlarm.events` |

---

## Definition of Done

□ `WarmAlarm.init()` silently re-registers future alarms on all three platforms (no events emitted)
□ `WarmAlarmBootReceiver` handles Android reboot recovery (no Flutter engine required)
□ `WarmAlarm.hasAlarm()` and `WarmAlarm.getAlarm(id)` are available on the facade
□ `WarmAlarmSchedule.androidFullScreenIntent` controls full-screen notification on Android
□ All Pigeon schemas updated and regenerated for all 3 platforms
□ All new fields mapped in Android/iOS/macOS Dart wrappers
□ melos run test passes (all 5 packages)
□ flutter build apk --debug passes
□ flutter build ios --no-codesign passes
□ flutter build macos passes
