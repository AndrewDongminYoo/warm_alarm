# Phase 3: Parity Features — `isRinging`, Payload, Enriched Snapshot, Volume Fade, Notification Customization

> **Status:** DRAFT — pending approval before implementation begins.

**Goal:** Close the feature gap identified in
`docs/notes/2026-05-02-alarm-to-warm-alarm-migration-analysis.md` between `alarm` and
`warm_alarm`. Phase 3 ships the four high-priority gaps plus the medium-priority audio and
notification improvements.

**Architecture note:** All new schedule-level fields follow the established pattern:

1. add a field to the public model in `warm_alarm_platform_interface`
2. add the corresponding wire field to each platform Pigeon schema
3. regenerate (`melos run generate`)
4. map in each platform Dart wrapper
5. implement natively

---

## Scope

### In Phase 3

| Task group            | Feature                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------- |
| **P** — Public models | `isRinging(int? id)` API                                                                  |
| **P**                 | `payload: String?` on `WarmAlarmSchedule`, `WarmAlarmSnapshot`, and `WarmAlarmEvent`      |
| **P**                 | Enriched `WarmAlarmSnapshot` — include full schedule fields recoverable from native store |
| **A**                 | Staircase volume fade — `WarmAlarmAudio.fadeSteps: List<WarmAlarmVolumeFadeStep>?`        |
| **A**                 | `volumeEnforced: bool` on `WarmAlarmAudio`                                                |
| **N**                 | Android notification icon (`WarmAlarmNotification.androidIcon: String?`)                  |
| **N**                 | Android notification icon color (`WarmAlarmNotification.androidIconColor: int?` — ARGB)   |
| **N**                 | iOS `keepNotificationAfterAlarmEnds: bool` on `WarmAlarmNotification`                     |
| **W**                 | App-kill warning notification — new `WarmAlarm.setKillWarning(title, body)` API           |

### Out of Phase 3 Scope

- Per-schedule `androidFullScreenIntent` toggle (capability already reported; may revisit)
- Per-schedule `allowAlarmOverlap` (undefined semantics; design first)
- Per-schedule `androidStopAlarmOnTermination` / `iOSBackgroundAudio` (niche flags)
- App-start rescheduling (`init()` / `checkAlarm()`) — complex enough for its own task group;
  deferred to Phase 4
- Live Activity (Phase 3+)
- Reactive state streams (app-layer concern; document pattern in example app instead)

---

## New Public Models

### `WarmAlarmVolumeFadeStep`

```dart
final class WarmAlarmVolumeFadeStep {
  const WarmAlarmVolumeFadeStep({
    required this.time,
    required this.volume,
  });

  final Duration time;   // offset from alarm start
  final double volume;   // 0.0–1.0
}
```

### Updated `WarmAlarmAudio`

```dart
final class WarmAlarmAudio {
  const WarmAlarmAudio({
    this.filePath,
    this.assetPath,
    this.loop = true,
    this.volume,
    this.fadeInDuration,
    this.fadeSteps,        // NEW — staircase fade; mutually exclusive with fadeInDuration
    this.volumeEnforced = false,  // NEW
    this.vibrate = true,
  });
  ...
  final List<WarmAlarmVolumeFadeStep>? fadeSteps;
  final bool volumeEnforced;
}
```

**Rule:** if both `fadeSteps` and `fadeInDuration` are provided, `fadeSteps` takes precedence.
If `fadeSteps` is empty when non-null, treat as no fade (or assert non-empty in constructor).

### Updated `WarmAlarmNotification`

```dart
final class WarmAlarmNotification {
  const WarmAlarmNotification({
    required this.title,
    required this.body,
    this.stopActionTitle,
    this.snoozeActionTitle,
    this.androidIcon,              // NEW — drawable resource name (Android only)
    this.androidIconColor,         // NEW — ARGB int (Android only)
    this.keepNotificationAfterAlarmEnds = false,  // NEW — iOS only
  });
  ...
}
```

### Updated `WarmAlarmSchedule`

```dart
final class WarmAlarmSchedule {
  const WarmAlarmSchedule({
    required this.id,
    required this.scheduledAt,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
    this.wakeCheck,
    this.payload,   // NEW
  });
  ...
  final String? payload;
}
```

### Updated `WarmAlarmSnapshot`

Current `WarmAlarmSnapshot` returns only `{id, scheduledAt}`. Enriched version returns the full
schedule data that is already persisted in the native store:

```dart
final class WarmAlarmSnapshot {
  const WarmAlarmSnapshot({
    required this.id,
    required this.scheduledAt,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
    this.wakeCheck,
    this.payload,
  });
  ...
}
```

This makes `getScheduledAlarms()` the source of truth for displaying alarm details without
requiring an app-layer Dart store.

### Updated `WarmAlarmEvent` — payload propagation

`WarmAlarmFired`, `WarmAlarmStopped`, `WarmAlarmSnoozed`, and `WarmAlarmRetriggered` should
carry `payload: String?` so event handlers can identify which alarm fired without querying
`getScheduledAlarms()`.

### New platform API method: `isRinging`

```dart
abstract class WarmAlarmPlatform extends PlatformInterface {
  ...
  Future<bool> isRinging({int? id});
}
```

Semantics: if `id` is provided, returns whether that specific alarm is currently ringing (i.e.
its ForegroundService / AVAudioPlayer is active). If `id` is null, returns whether any alarm is
ringing.

### New platform API method: `setKillWarning`

```dart
abstract class WarmAlarmPlatform extends PlatformInterface {
  ...
  Future<void> setKillWarning({required String title, required String body});
  Future<void> clearKillWarning();
}
```

On iOS: schedules a local notification at the moment the app moves to background while an alarm
is active. On Android: optional; Android alarms fire via AlarmManager even if the app is killed,
so the warning is less critical but still available.

---

## Task List

### Group P1: `isRinging` API

- [ ] **P1a** Add `Future<bool> isRinging({int? id})` to `WarmAlarmPlatform`
- [ ] **P1b** Add `isRinging` to `WarmAlarm` facade
- [ ] **P1c** Add `isRinging(int? alarmId)` to Android Pigeon `WarmAlarmApi` (HostApi, sync or async)
- [ ] **P1d** Add `isRinging(int? alarmId)` to iOS Pigeon `WarmAlarmApi`
- [ ] **P1e** Add `isRinging(int? alarmId)` to macOS Pigeon `WarmAlarmApi`
- [ ] **P1f** `melos run generate`
- [ ] **P1g** Implement `isRinging` in Android Kotlin (`WarmAlarmPlugin`): check if ForegroundService is running for the given id; if id null, check for any
- [ ] **P1h** Implement `isRinging` in iOS Swift (`WarmAlarmPlugin`): check delegate audio player state
- [ ] **P1i** Implement `isRinging` in macOS Swift: same pattern as iOS
- [ ] **P1j** Map in Android/iOS/macOS Dart wrappers
- [ ] **P1k** Add tests

### Group P2: `payload` propagation

- [ ] **P2a** Add `payload: String?` to `WarmAlarmSchedule`
- [ ] **P2b** Add `payload: String?` to `WarmAlarmSnapshot`
- [ ] **P2c** Add `payload: String?` to `WarmAlarmFired`, `WarmAlarmStopped`, `WarmAlarmSnoozed`, `WarmAlarmRetriggered`
- [ ] **P2d** Add `payload: String?` to Android `WarmAlarmScheduleWire`, `WarmAlarmSnapshotWire`, `WarmAlarmEventWire`
- [ ] **P2e** Add `payload: String?` to iOS / macOS Pigeon schemas
- [ ] **P2f** `melos run generate`
- [ ] **P2g** Persist `payload` in Android `WarmAlarmStore` (encode/decode JSON field)
- [ ] **P2h** Persist `payload` in iOS/macOS `WarmAlarmStore` (Codable field)
- [ ] **P2i** Propagate `payload` through Android Kotlin event emission (Fired, Stopped, Snoozed, Retriggered)
- [ ] **P2j** Propagate `payload` through iOS/macOS Swift event emission
- [ ] **P2k** Map `payload` in all Dart wrappers
- [ ] **P2l** Add tests

### Group P3: Enriched `WarmAlarmSnapshot`

- [ ] **P3a** Add all `WarmAlarmSchedule` fields to `WarmAlarmSnapshot` (notification, audio, recurrence, snooze, wakeCheck, payload)
- [ ] **P3b** Update Android `WarmAlarmSnapshotWire` with the new fields
- [ ] **P3c** Update iOS/macOS `WarmAlarmSnapshotWire`
- [ ] **P3d** `melos run generate`
- [ ] **P3e** Update Android `WarmAlarmPlugin.getScheduledAlarms()` to reconstruct full snapshot from store
- [ ] **P3f** Update iOS/macOS equivalent
- [ ] **P3g** Map in Dart wrappers
- [ ] **P3h** Add tests

### Group A1: Staircase volume fade

- [ ] **A1a** Add `WarmAlarmVolumeFadeStep` class to platform interface
- [ ] **A1b** Add `fadeSteps: List<WarmAlarmVolumeFadeStep>?` and `volumeEnforced: bool` to `WarmAlarmAudio`
- [ ] **A1c** Add `WarmAlarmVolumeFadeStepWire` and fields to Android `WarmAlarmAudioWire`
- [ ] **A1d** Add to iOS/macOS Pigeon schemas
- [ ] **A1e** `melos run generate`
- [ ] **A1f** Implement staircase fade in Android Kotlin (`WarmAlarmForegroundService` audio player)
- [ ] **A1g** Implement in iOS/macOS Swift (`WarmAlarmDelegate` AVAudioPlayer + volume ramp timer)
- [ ] **A1h** Implement `volumeEnforced` in Android (volume listener on `AudioManager`)
- [ ] **A1i** Map in Dart wrappers
- [ ] **A1j** Add tests

### Group N1: Notification customization

- [ ] **N1a** Add `androidIcon: String?`, `androidIconColor: int?`, `keepNotificationAfterAlarmEnds: bool` to `WarmAlarmNotification`
- [ ] **N1b** Add to Android `WarmAlarmNotificationWire`
- [ ] **N1c** Add to iOS/macOS Pigeon schemas (fields present but ignored on iOS/macOS for `androidIcon`/`androidIconColor`)
- [ ] **N1d** `melos run generate`
- [ ] **N1e** Apply `androidIcon` and `androidIconColor` in Android notification builder
- [ ] **N1f** Implement `keepNotificationAfterAlarmEnds` in iOS (`WarmAlarmDelegate`: don't remove UNNotification on audio end if flag is set)
- [ ] **N1g** Map in Dart wrappers
- [ ] **N1h** Add tests

### Group W1: App-kill warning notification

- [ ] **W1a** Add `setKillWarning(title, body)` and `clearKillWarning()` to `WarmAlarmPlatform` and `WarmAlarm` facade
- [ ] **W1b** Add `setKillWarning` / `clearKillWarning` to Android Pigeon `WarmAlarmApi`
- [ ] **W1c** Add to iOS/macOS Pigeon schemas
- [ ] **W1d** `melos run generate`
- [ ] **W1e** Implement in Android Kotlin: store title/body in `SharedPreferences`; schedule a local notification in `onTaskRemoved` of `WarmAlarmForegroundService` if alarm active
- [ ] **W1f** Implement in iOS Swift: subscribe to `UIApplication.willResignActiveNotification`; schedule a `UNNotificationRequest` with a 1-second delay if alarm active; cancel on foreground
- [ ] **W1g** Implement in macOS Swift: equivalent lifecycle hook
- [ ] **W1h** Map in Dart wrappers
- [ ] **W1i** Add tests

---

## Definition of Done

□ WarmAlarmPlatform exposes isRinging({int? id}) and setKillWarning/clearKillWarning
□ WarmAlarmSchedule, WarmAlarmSnapshot, and relevant WarmAlarmEvent subtypes carry payload
□ WarmAlarmSnapshot returns full schedule data (reconstructable from getScheduledAlarms())
□ WarmAlarmAudio supports fadeSteps (staircase) and volumeEnforced
□ WarmAlarmNotification supports androidIcon, androidIconColor, keepNotificationAfterAlarmEnds
□ All new Pigeon fields regenerated for all 3 platforms
□ All new fields mapped in Android/iOS/macOS Dart wrappers
□ melos run test passes (all 5 packages)
□ flutter build apk --debug passes
□ flutter build ios --no-codesign passes
□ flutter build macos passes
