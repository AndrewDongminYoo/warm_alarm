# Phase 4: App-Start Recovery, Convenience API, and Per-Schedule Platform Flags

> **Status:** DRAFT — pending approval before implementation begins.

**Goal:** Close the remaining feature gaps between `alarm` and `warm_alarm` identified in
`docs/notes/2026-05-02-alarm-to-warm-alarm-migration-analysis.md`. Phase 3 shipped parity
features (isRinging, payload, staircase fade, notification customization, kill-warning).
Phase 4 addresses the harder structural gaps: app-start alarm recovery, convenience query
methods, and optional per-schedule Android platform flags.

**Architecture note:** Phase 4 introduces no new Pigeon wire types for Groups C1 and F1.
Group R1 (recovery) requires a new `WarmAlarm.init()` API that drives an existing
`getScheduledAlarms()` → reschedule loop entirely from Dart.

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
  /// - Fetches [getScheduledAlarms()] from the native store.
  /// - For alarms whose [WarmAlarmSnapshot.scheduledAt] is still in the future,
  ///   re-schedules them via [scheduleAlarm] to ensure the native scheduler has
  ///   not been cleared (relevant on Android after a device reboot with no
  ///   RECEIVE_BOOT_COMPLETED receiver, or on iOS after an app update).
  /// - Emits no events for already-past alarms; callers must handle the
  ///   missed-alarm case by checking [isRinging] or listening to [events].
  static Future<void> init() => _platform.init();
}
```

**Android notes:**

- `AlarmManager.setExactAndAllowWhileIdle` alarms survive process death but are
  cleared on device reboot unless `RECEIVE_BOOT_COMPLETED` is declared. Phase 4
  adds a `BootReceiver` that iterates the `WarmAlarmStore` and reschedules.
- `init()` on Android checks which store entries have a `scheduledAtMillis` in the
  future and calls `setExactAndAllowWhileIdle` for each.

**iOS/macOS notes:**

- Pending `UNNotificationRequest`s survive app restarts natively; `init()` can be
  a no-op or a cross-check (verify store entries against pending notification IDs
  and re-add any that are missing).

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

- [ ] **R1a** Add `Future<void> init()` to `WarmAlarmPlatform` abstract class
- [ ] **R1b** Add a default implementation to `WarmAlarmPlatform.init()` that:
  - fetches `getScheduledAlarms()`
  - filters to entries with `scheduledAt.isAfter(DateTime.now())`
  - calls `scheduleAlarm(WarmAlarmSchedule.fromSnapshot(s))` for each

  > `WarmAlarmSchedule.fromSnapshot` is a factory constructor to add in this group.

- [ ] **R1c** Add `WarmAlarm.init()` to the facade
- [ ] **R1d** Add `WarmAlarmSchedule.fromSnapshot(WarmAlarmSnapshot)` factory constructor
- [ ] **R1e** Override `init()` in Android Dart wrapper to no-op (default base impl handles it via `scheduleAlarm`)
- [ ] **R1f** Override `init()` in iOS/macOS Dart wrapper — same default impl is sufficient; add override only if iOS needs a cross-check with pending notification IDs
- [ ] **R1g** Add `RECEIVE_BOOT_COMPLETED` permission to Android `AndroidManifest.xml`
- [ ] **R1h** Add `WarmAlarmBootReceiver` Kotlin class: on boot, load store and reschedule all future alarms
- [ ] **R1i** Register `WarmAlarmBootReceiver` in `AndroidManifest.xml`
- [ ] **R1j** Add tests

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

□ `WarmAlarm.init()` reschedules future alarms recovered from native store
□ `WarmAlarmBootReceiver` handles Android reboot recovery
□ `WarmAlarm.hasAlarm()` and `WarmAlarm.getAlarm(id)` are available on the facade
□ `WarmAlarmSchedule.androidFullScreenIntent` controls full-screen notification on Android
□ `WarmAlarmSchedule.fromSnapshot(WarmAlarmSnapshot)` factory constructor available
□ All Pigeon schemas updated and regenerated for all 3 platforms
□ All new fields mapped in Android/iOS/macOS Dart wrappers
□ melos run test passes (all 5 packages)
□ flutter build apk --debug passes
□ flutter build ios --no-codesign passes
□ flutter build macos passes
