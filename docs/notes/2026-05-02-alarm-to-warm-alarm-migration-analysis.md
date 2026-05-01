# Migration Analysis: `alarm` → `warm_alarm`

**Date:** 2026-05-02  
**Purpose:** Document feature gaps and migration considerations when replacing the
`alarm` package with `warm_alarm`.

---

## Executive Summary

`alarm` is a monolithic plugin (single package, single Pigeon schema, iOS + Android only).
`warm_alarm` is a federated plugin family (5 packages, per-platform Pigeon schemas, Android +
iOS + macOS) with a richer capability/permission/readiness model and a formal public/wire model
boundary.

`warm_alarm` Phase 1+2 covers the core alarm loop plus wake-check on Android. Several
`alarm`-side features — most notably `isRinging()`, per-schedule platform flags, Dart-side
schedule storage, volume staircase fade, notification icon customization, app-kill warning
notifications, and a `payload` passthrough — are not yet implemented.

---

## API Surface Comparison

### Scheduling

| Concern     | `alarm`                                     | `warm_alarm`                                                                         |
| ----------- | ------------------------------------------- | ------------------------------------------------------------------------------------ |
| Schedule    | `Alarm.set(alarmSettings:)` → `bool`        | `WarmAlarm.scheduleAlarm(schedule)` → `WarmAlarmScheduleResult`                      |
| Cancel one  | `Alarm.stop(id)` → `bool`                   | `WarmAlarm.cancelAlarm(id)` → `void`                                                 |
| Cancel all  | `Alarm.stopAll()`                           | `WarmAlarm.cancelAllAlarms()`                                                        |
| Query by id | `Alarm.getAlarm(id)` → `AlarmSettings?`     | ❌ not available                                                                     |
| Query all   | `Alarm.getAlarms()` → `List<AlarmSettings>` | `WarmAlarm.getScheduledAlarms()` → `List<WarmAlarmSnapshot>` (id + scheduledAt only) |
| Has alarm   | `Alarm.hasAlarm()` → `bool`                 | ❌ not available                                                                     |
| Is ringing  | `Alarm.isRinging([id])` → `bool`            | ❌ not available                                                                     |

### State / Streams

| Concern       | `alarm`                                              | `warm_alarm`                                              |
| ------------- | ---------------------------------------------------- | --------------------------------------------------------- |
| Scheduled set | `Alarm.scheduled` — `ValueStream<AlarmSet>` (rxdart) | ❌ derive from `events` stream                            |
| Ringing set   | `Alarm.ringing` — `ValueStream<AlarmSet>` (rxdart)   | ❌ derive from `events` stream                            |
| Event stream  | deprecated `ringStream` / `updateStream`             | `WarmAlarm.events` — `Stream<WarmAlarmEvent>` (broadcast) |

### Initialization

| Concern            | `alarm`                                                                      | `warm_alarm`                                                                            |
| ------------------ | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| App start          | `Alarm.init()` — sets up Pigeon callback, storage, reschedules missed alarms | ❌ no equivalent; platform implementations start listening on first event stream access |
| Post-kill recovery | `Alarm.checkAlarm()` — re-schedules alarms whose DateTime is in the future   | ❌ not available                                                                        |

### Platform Capabilities

| Concern          | `alarm`             | `warm_alarm`                                       |
| ---------------- | ------------------- | -------------------------------------------------- |
| Capability query | ❌ not available    | `WarmAlarm.getCapabilities()`                      |
| Permission query | ❌ not available    | `WarmAlarm.getPermissionState()`                   |
| Readiness query  | ❌ not available    | `WarmAlarm.getReadiness()`                         |
| Schedule result  | `bool` success flag | `WarmAlarmScheduleResult` with readiness + warning |

---

## Audio Features

| Feature             | `alarm`                                                                          | `warm_alarm`                         |
| ------------------- | -------------------------------------------------------------------------------- | ------------------------------------ |
| Asset path          | `assetAudioPath: String?`                                                        | `WarmAlarmAudio.assetPath`           |
| File path           | ❌ same field with path convention                                               | `WarmAlarmAudio.filePath` (explicit) |
| Loop                | `loopAudio: bool`                                                                | `WarmAlarmAudio.loop`                |
| Volume              | `VolumeSettings.volume: double?`                                                 | `WarmAlarmAudio.volume: double?`     |
| Simple fade-in      | `VolumeSettings.fade(fadeDuration:)`                                             | `WarmAlarmAudio.fadeInDuration`      |
| **Staircase fade**  | `VolumeSettings.staircaseFade(fadeSteps:)` — `List<VolumeFadeStep>`              | ❌ not available                     |
| **Volume enforced** | `VolumeSettings.volumeEnforced: bool` — prevents user from lowering alarm volume | ❌ not available                     |
| Vibrate             | `vibrate: bool`                                                                  | `WarmAlarmAudio.vibrate`             |

`VolumeFadeStep` is a `{time: Duration, volume: double}` tuple that lets the alarm ramp volume
through multiple checkpoints (e.g. 0% → 25% at 10s → 100% at 30s). This is richer than a
single linear fade.

---

## Notification Features

| Feature                 | `alarm`                                                       | `warm_alarm`                              |
| ----------------------- | ------------------------------------------------------------- | ----------------------------------------- |
| Title                   | `NotificationSettings.title`                                  | `WarmAlarmNotification.title`             |
| Body                    | `NotificationSettings.body`                                   | `WarmAlarmNotification.body`              |
| Stop action             | `NotificationSettings.stopButton`                             | `WarmAlarmNotification.stopActionTitle`   |
| Snooze action           | ❌ not available                                              | `WarmAlarmNotification.snoozeActionTitle` |
| **Android icon**        | `NotificationSettings.icon: String?` (drawable resource name) | ❌ not available                          |
| **Android icon color**  | `NotificationSettings.iconColor: Color?`                      | ❌ not available                          |
| **iOS keep after ends** | `NotificationSettings.keepNotificationAfterAlarmEnds: bool`   | ❌ not available                          |

---

## Per-Schedule Platform Flags

These are per-alarm configuration knobs in `alarm` that `warm_alarm` does not yet expose.

| Flag                            | `alarm` field                                          | Meaning                                                                       |
| ------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| **Full-screen intent**          | `androidFullScreenIntent: bool` (default `true`)       | Turn on screen and show full-screen notification on Android                   |
| **Allow overlap**               | `allowAlarmOverlap: bool` (default `false`)            | Ring even if another alarm is already ringing                                 |
| **iOS background audio**        | `iOSBackgroundAudio: bool` (default `true`)            | Play silent audio on iOS to prevent app being killed while alarm is scheduled |
| **Android stop on termination** | `androidStopAlarmOnTermination: bool` (default `true`) | Stop alarm when user swipes away the app                                      |
| **Warning on kill**             | `warningNotificationOnKill: bool` (default `true`)     | Show notification when user kills the app (especially important on iOS)       |

`warm_alarm` exposes `fullScreenPresentation` as a **capability status**, not as a per-schedule
toggle. The others have no equivalent at all yet.

---

## App-Kill Warning Notification

`alarm` provides `Alarm.setWarningNotificationOnKill(title, body)` and
`AndroidAlarm.disableWarningNotificationOnKill()` for customizing or suppressing the notification
shown when the user kills the app while an alarm is scheduled. On iOS this is critical because
the native alarm cannot fire if the app process is dead.

`warm_alarm` has no equivalent yet.

---

## Payload / User Data

`alarm` provides `AlarmSettings.payload: String?` for callers to attach arbitrary serialized data
to an alarm and retrieve it when the event arrives. `warm_alarm` has no payload field on either
`WarmAlarmSchedule` or `WarmAlarmSnapshot` or `WarmAlarmEvent`.

---

## State Model Differences

### `alarm`: push-down state (BehaviorSubject)

`alarm` maintains `scheduled` and `ringing` as `BehaviorSubject<AlarmSet>` from `rxdart`. Any
subscriber can always synchronously read `.value` without needing to wait for an event. Both
streams are updated whenever the Dart layer is notified of a change.

### `warm_alarm`: events-only broadcast stream

`warm_alarm` exposes a `Stream<WarmAlarmEvent>` broadcast stream. Callers must build their own
state layer on top of it. There is no built-in way to answer "which alarms are currently
ringing?" without tracking events from app start.

**Migration implication:** Apps that relied on `Alarm.ringing.value` for immediate synchronous
reads need to implement a `WarmAlarmStateNotifier` (or equivalent Riverpod/Bloc layer) that
folds `WarmAlarmEvent`s into a local state snapshot.

---

## Storage / Snapshot Model

`alarm` stores the full `AlarmSettings` JSON in `SharedPreferences` on the Dart side. After an
app restart, `Alarm.checkAlarm()` restores all scheduled alarms from storage and re-schedules
any whose `DateTime` is still in the future.

`warm_alarm` stores schedules natively (Kotlin `SharedPreferences` / Swift `UserDefaults`).
`getScheduledAlarms()` returns `List<WarmAlarmSnapshot>` — only `id` and `scheduledAt`. The
full `WarmAlarmSchedule` (audio, notification, recurrence, wake-check config) is not
reconstructable from the Dart API. Apps that need to display alarm details must maintain their
own Dart-side store keyed on `id`.

---

## Pigeon Architecture

| Aspect                      | `alarm`                                                            | `warm_alarm`                                                                             |
| --------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| Pigeon scope                | Single schema for all platforms                                    | Per-platform schemas (Android / iOS / macOS each have their own `pigeons/messages.dart`) |
| FlutterApi                  | `AlarmTriggerApi` — `alarmRang(alarmId)` + `alarmStopped(alarmId)` | `WarmAlarmEventsApi` — `emitEvent(WarmAlarmEventWire)` with typed enum for event type    |
| Wire DTOs exported publicly | No (under `src/generated/`)                                        | No (under `lib/src/`)                                                                    |
| Event richness              | 2 callbacks                                                        | 9 event types (sealed class hierarchy)                                                   |

`alarm` uses a separate `@FlutterApi` with individual methods per event. `warm_alarm` uses a
single `emitEvent` with a discriminated union wire type — more extensible but requires switch
exhaustiveness on the Dart side.

---

## Fallback / Resilience

`alarm` ships a `PlatformTimers` Dart-side polling fallback: a `Timer.periodic` at 200ms that
fires the alarm callback from Dart if the native callback hasn't arrived. It also subscribes to
`FGBGEvents` (flutter_fgbg) to track foreground/background transitions and pause/resume the
timer.

`warm_alarm` relies entirely on the native `WarmAlarmEventsApi` Pigeon callback. There is no
Dart-side fallback. This is architecturally cleaner but increases dependency on the native
channel being reliably delivered — which on Android with AlarmManager exact alarms and a
ForegroundService is generally reliable.

---

## Platform Coverage

| Platform        | `alarm` | `warm_alarm`                                              |
| --------------- | ------- | --------------------------------------------------------- |
| Android         | ✅ full | ✅ full (Phase 1B + Phase 2)                              |
| iOS             | ✅ full | ✅ Phase 1C (notification-driven, limited wake semantics) |
| macOS           | ❌      | ✅ Phase 1C (notification-driven)                         |
| Windows / Linux | ❌      | ❌                                                        |

---

## Feature Gap Summary

Features in `alarm` not yet implemented in `warm_alarm`, ordered by estimated migration impact:

| Priority  | Feature                                            | Notes                                                                                |
| --------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 🔴 High   | `isRinging([id])`                                  | Fundamental alarm state query; needed to reconstruct ringing state after app restart |
| 🔴 High   | App-start rescheduling (`init()` / `checkAlarm()`) | Without this, scheduled alarms are lost after process restart on some devices        |
| 🔴 High   | `payload: String?` on schedule                     | User data passthrough; many apps depend on this to associate alarm context           |
| 🟡 Medium | Enriched `WarmAlarmSnapshot`                       | Full schedule data recoverable from `getScheduledAlarms()`                           |
| 🟡 Medium | Staircase volume fade (`List<VolumeFadeStep>`)     | Graduated volume ramping                                                             |
| 🟡 Medium | `volumeEnforced`                                   | Alarm clock UX: prevent user from lowering alarm                                     |
| 🟡 Medium | App-kill warning notification (iOS)                | Users expect to be warned that the alarm will fail if iOS kills the app              |
| 🟡 Medium | Android notification icon + icon color             | Branding in the notification shade                                                   |
| 🟠 Low    | `keepNotificationAfterAlarmEnds` (iOS)             | Edge case for non-looping alarms                                                     |
| 🟠 Low    | `allowAlarmOverlap` per-schedule                   | Overlap semantics currently undefined in warm_alarm                                  |
| 🟠 Low    | `androidStopAlarmOnTermination` per-schedule       | Niche Android flag                                                                   |
| 🟠 Low    | `iOSBackgroundAudio` per-schedule                  | Niche iOS flag for apps with existing background audio                               |
