# Phase 2: Android Wake-Check & Retrigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in wake-check flow on Android: after alarm dismissal, schedule a follow-up check alarm; if the user does not acknowledge they are awake within a configured window, retrigger the alarm.

**Architecture:** `WarmAlarmWakeCheck` added as an optional field on `WarmAlarmSchedule` in the platform interface. Four new public event types: `WarmAlarmWakeCheckShown`, `WarmAlarmWakeCheckDismissed`, `WarmAlarmWakeCheckExpired`, `WarmAlarmRetriggered`. Android Pigeon schema extended with `WarmAlarmWakeCheckWire` and four new `WarmAlarmEventTypeWire` values. `WarmAlarmForegroundService` schedules a `ACTION_WAKE_CHECK_FIRE` alarm after STOP; `WarmAlarmReceiver` handles the new actions. **iOS and macOS Pigeon schemas are not changed** — `wakeCheck` capability is already declared `unsupported` on Apple platforms.

**Tech Stack:** Dart 3.11, Pigeon, Kotlin, Android `AlarmManager` + `BroadcastReceiver`, `flutter_test`, `mocktail`, `melos`

---

## Wake-Check Event Flow (Android)

```
t=0      Alarm fires               → WarmAlarmFired
         User presses STOP         → WarmAlarmStopped
                                     (schedule check alarm at t+checkDelay)
t+check  Check alarm fires         → WarmAlarmWakeCheckShown
                                     (show "I'm awake?" notification)
                                     (schedule retrigger alarm at t+check+retriggerDelay)
  4a     User taps "I'm awake"     → WarmAlarmWakeCheckDismissed (cancel retrigger)
  4b     Retrigger alarm fires     → WarmAlarmWakeCheckExpired
                                   → WarmAlarmRetriggered
                                     (restart ForegroundService; alarm plays again)
         User stops retriggered    → WarmAlarmStopped
                                     (no further checks: retriggerCount >= maxRetriggers)
```

---

## Key Design Decisions

- **`WarmAlarmStore.remove()` moved from `handleFire` to `handleStop`**: The store entry must persist while the alarm is ringing so `handleStop` can read wake-check config. Also fixes the pre-existing snooze bug where `WarmAlarmStore.reschedule()` was a no-op.
- **Retrigger count stored separately**: `retriggerCount` is operational runtime state, not schedule config. It is stored in SharedPreferences under key `retrigger_<alarmId>` and cleared on `remove()`.
- **`CHANNEL_ID` made public**: `WarmAlarmForegroundService.CHANNEL_ID` changed from `private` to `internal`/public so `WarmAlarmReceiver` can build wake-check notifications on the same channel.
- **PendingIntent offsets**: `WAKE_CHECK_PENDING_OFFSET = 30_000` (wake-check alarm requestCode), `WAKE_CHECK_NOTIF_OFFSET = 20_000` (wake-check notification ID) to avoid collision with main alarm PendingIntents.

---

## File Map

### Platform interface (hand-written public models)

- Created: `warm_alarm_platform_interface/lib/src/models/warm_alarm_wake_check.dart`
- Modified: `warm_alarm_platform_interface/lib/src/models/warm_alarm_schedule.dart`
- Modified: `warm_alarm_platform_interface/lib/src/models/warm_alarm_event.dart`
- Modified: `warm_alarm_platform_interface/lib/src/models/models.dart`
- Modified: `warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`

### Android Pigeon (extend schema, regenerate)

- Modified: `warm_alarm_android/pigeons/messages.dart`
- Regenerated: `warm_alarm_android/lib/src/messages.g.dart`
- Regenerated: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/Messages.g.kt`

### Android Dart wrapper

- Modified: `warm_alarm_android/lib/warm_alarm_android.dart`
- Modified: `warm_alarm_android/test/warm_alarm_android_test.dart`

### Android Kotlin native

- Modified: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt`
- Modified: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmPlugin.kt`
- Modified: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmReceiver.kt`
- Modified: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt`
- Modified: `warm_alarm_android/android/src/main/AndroidManifest.xml`

### Example app

- Modified: `warm_alarm/example/lib/main.dart`

### Project docs

- Created: `docs/plans/2026-05-01-warm-alarm-phase-2-implementation-plan.md`

---

## Tasks Completed

### Task F0: Save Phase 1C Plan Document

- **Commit:** `2ce6ef6` — docs: save Phase 1C Apple alarm proof implementation plan

### Task P1: Add WarmAlarmWakeCheck Model and Wake-Check Event Types

- `WarmAlarmWakeCheck` model: `checkDelay` (required), `retriggerDelay` (optional), `maxRetriggers` (default 1)
- `WarmAlarmSchedule.wakeCheck` optional field added
- 4 new sealed subclasses appended to `warm_alarm_event.dart`: `WarmAlarmWakeCheckShown`, `WarmAlarmWakeCheckDismissed`, `WarmAlarmWakeCheckExpired`, `WarmAlarmRetriggered`
- `models.dart` export updated
- 8 new tests added; all 10 platform interface tests pass
- **Commit:** `35c44e9` — feat: add WarmAlarmWakeCheck model and wake-check event types to platform interface

### Task P2: Update Android Pigeon Schema and Regenerate

- `WarmAlarmWakeCheckWire` class added with `checkDelayMillis`, `retriggerDelayMillis?`, `maxRetriggers?`
- `WarmAlarmScheduleWire.wakeCheck: WarmAlarmWakeCheckWire?` field added
- 4 new `WarmAlarmEventTypeWire` values: `wakeCheckShown`, `wakeCheckDismissed`, `wakeCheckExpired`, `retriggered`
- `melos run generate` executed; iOS/macOS generated files also updated (formatting changes only)
- `flutter build apk --debug` passes
- **Commit:** `ab943a8` — feat(android): extend Pigeon schema with WarmAlarmWakeCheckWire and wake-check event types

### Task P3: Android Dart Wrapper — Schedule Mapping + Event Mapping + Tests

- `_wakeCheckToWire()` helper function added
- `_scheduleToWire()` passes `wakeCheck: _wakeCheckToWire(schedule.wakeCheck)`
- `_eventFromWire()` switch extended with 4 new cases
- 6 new tests (4 event mapping + 2 schedule wakeCheck wire mapping); all 15 Android tests pass
- **Commit:** `01e2033` — feat(android): add wake-check event mapping and wakeCheck schedule wire mapping in Dart

### Task A1: Android Kotlin — WarmAlarmStore Wake-Check Fields

- `encode()` serializes `wakeCheck` JSON object with `checkDelayMillis`, `retriggerDelayMillis?`, `maxRetriggers?`
- `decode()` restores `wakeCheck` from JSON with backward-compatible `has()` guards
- `getRetriggerCount(context, id)` reads from `retrigger_<id>` prefs key (default 0)
- `incrementRetriggerCount(context, id)` increments the prefs key
- `remove()` now also clears `retrigger_<id>` prefs key
- **Commit:** `4d1edf7` — feat(android): add wake-check fields to WarmAlarmStore

### Task A2: Android Kotlin — Receiver + ForegroundService Wake-Check

- `WarmAlarmReceiver`: added `ACTION_WAKE_CHECK_FIRE`, `ACTION_WAKE_CHECK_DISMISS`, `EXTRA_IS_RETRIGGER` constants; `onReceive` dispatches to 3 handlers; `handleAlarmFire` emits FIRED or WAKE_CHECK_EXPIRED+RETRIGGERED; `handleWakeCheckFire` emits WAKE_CHECK_SHOWN, shows notification, schedules retrigger; `handleWakeCheckDismiss` cancels retrigger, removes store, emits WAKE_CHECK_DISMISSED
- `WarmAlarmPlugin.rescheduleAlarm`: `isRetrigger: Boolean = false` parameter added
- `WarmAlarmForegroundService`: `CHANNEL_ID` made public; `WarmAlarmStore.remove()` moved from `handleFire` to `handleStop`; `handleStop` conditionally schedules wake-check or removes store; `scheduleWakeCheck()` helper added; `WAKE_CHECK_PENDING_OFFSET = 30_000` constant added
- `AndroidManifest.xml`: 2 new intent-filter blocks for wake-check actions
- **Commit:** `5471ea8` — feat(android): implement wake-check scheduling, retrigger, and dismiss in Receiver + ForegroundService

---

## Definition of Done

```
✓ WarmAlarmWakeCheck public model in platform interface
✓ WarmAlarmSchedule.wakeCheck optional field
✓ WarmAlarmWakeCheckShown, WarmAlarmWakeCheckDismissed, WarmAlarmWakeCheckExpired, WarmAlarmRetriggered event types
✓ Android Pigeon: WarmAlarmWakeCheckWire + 4 new event type enum values
✓ Android Dart: _wakeCheckToWire mapping + _eventFromWire new cases
✓ Android: WarmAlarmStore persists wake-check config + retriggerCount
✓ Android: ForegroundService schedules wake-check alarm after STOP
✓ Android: WarmAlarmReceiver handles ACTION_WAKE_CHECK_FIRE (show notification + schedule retrigger)
✓ Android: WarmAlarmReceiver handles ACTION_WAKE_CHECK_DISMISS (cancel retrigger, emit dismissed)
✓ Android: Retrigger fire emits WakeCheckExpired + Retriggered, increments retriggerCount
✓ melos run test passes (all 5 packages)
✓ flutter build apk --debug passes
```

## Not in Phase 2 Scope (Phase 3+)

- iOS/macOS wake-check: `wakeCheck` remains `unsupported` on Apple platforms
- iOS Live Activity / ActivityKit integration
- iOS request-permission from Dart
- Reboot persistence for wake-check alarms (would require BOOT_COMPLETED re-scheduling)
- Wake-check for snoozed alarms (only fires after STOP, not after SNOOZE)
