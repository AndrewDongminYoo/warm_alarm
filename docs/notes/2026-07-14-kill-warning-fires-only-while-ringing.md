# Kill-Warning Fires Only While Ringing (should fire while an alarm is scheduled)

**Date:** 2026-07-14
**Status:** Fixed on Android (2026-07-14). iOS/macOS improved (2026-07-14) with a `willTerminate`
observer — the originally proposed guard-broaden on the resign-active hook was unsafe (see the
corrected analysis below), so it was added on a real-termination hook instead. Raised from the
consuming app (WarmWake) during warm_alarm integration review.

## Problem

`setKillWarning(title:body:)` stores a title/body that the OS is meant to show if the user force-quits the app while an alarm could still fire. This supersets the `alarm` package's `setWarningNotificationOnKill` + per-alarm `warningNotificationOnKill` flag, whose purpose is to warn the user when they swipe the app away **while an alarm is scheduled** — the dominant failure mode on aggressive OEMs, where a swiped-away app never wakes to ring.

The current native implementation fires the warning **only when an alarm is actively ringing at kill time**, which is a much narrower case than intended. If the user schedules an alarm for 07:00 and swipes the app away at 23:00, no warning is posted — exactly the situation the feature exists to cover.

## Current behavior (all three platforms share the same narrow guard)

- **iOS** — `WarmAlarmPlugin.postKillWarningIfNeeded()` guards `delegate.currentlyPlayingAlarmId != nil`. Fires only if an alarm is ringing.
- **macOS** — same guard `currentlyPlayingAlarmId != nil`.
- **Android** — the warning is posted from `WarmAlarmForegroundService.onTaskRemoved` behind `if (isRinging)`. The foreground service only runs while an alarm is ringing, so `onTaskRemoved` cannot fire for a merely-scheduled alarm — the swipe-away-while-scheduled case produces no warning at all.

## Intended behavior (parity with the `alarm` package)

Post the kill warning when the app is force-quit **and at least one future alarm is scheduled** (whether or not it is currently ringing). Ringing is a strict subset of "scheduled," so broadening the guard preserves the current case and adds the missing one.

## Fix (per platform)

- **Android (implemented 2026-07-14)** — `onTaskRemoved` in the foreground service is the wrong
  (too-late) hook because no service runs while merely scheduled. Added
  `WarmAlarmKillWarningService`: a bare started `Service` (`START_STICKY`, manifest
  `android:stopWithTask="false"` so the OS delivers `onTaskRemoved` on swipe rather than killing it
  silently). `WarmAlarmPlugin` starts it in `scheduleAlarm`/`initialize` (whenever a future alarm
  exists) and stops it in `cancelAlarm`/`cancelAllAlarms` once the store is empty. Its
  `onTaskRemoved` posts the warning when `WarmAlarmStore` has a future alarm **or** an alarm is
  ringing. This matches the `alarm` package's `NotificationOnKillService`. The existing
  `WarmAlarmForegroundService.onTaskRemoved` ringing path is left untouched; both share the same
  channel/notification id, so a swipe during ringing produces one notification, not two.
- **iOS / macOS (implemented 2026-07-14, additive)** — the note originally proposed "broaden the
  guard from `currentlyPlayingAlarmId != nil` to a future alarm exists". That is **unsafe as written**
  because the hook calling `postKillWarningIfNeeded()` is **not** termination — it is
  `UIScene.willDeactivate` / `UIApplication.willResignActive` (iOS) and `NSApplication.willResignActive`
  (macOS). That path is a dead-man's-switch: resign-active schedules the warning with a 1 s delay and
  cancels it on the next `didBecomeActive`. Broadening _its_ gate to "any scheduled alarm" would fire
  the warning on **every** normal backgrounding (home, app switch), since the 1 s timer elapses long
  before the user returns to cancel — constant false positives.

  Instead, the broadened guard was added on a genuine-termination hook: a new
  `willTerminate` observer (`postKillWarningOnTerminate` / `appWillTerminate`) posts the warning
  immediately (nil trigger, blocked on a `DispatchSemaphore` so the request enqueues before the
  process dies) for any alarm that is scheduled in the future **or** ringing. Because `willTerminate`
  fires only on a real quit, broadening its guard is spam-free. The existing resign-active mechanism
  is left untouched and **ringing-gated** — it is the only path that catches an iOS swipe-kill while
  an alarm is _ringing_ (the app is non-suspended then, so entering the switcher pre-schedules the
  warning). Both paths share the kill-warning notification id, so a ring-then-terminate coalesces to
  one notification.

  Known iOS limit (cannot be fixed by lifecycle observers): `willTerminate` is **not delivered to a
  suspended app** cleared from the app switcher — and a suspended app runs no code, so no observer or
  cancel scheme can catch that case. The only way to cover it is `iOSBackgroundAudio`-style silent
  playback that keeps the process non-suspended (as the `alarm` package does); that was **not**
  adopted here (battery / complexity / App Store background-audio review cost). So the dominant
  aggressive-OEM swipe-away failure mode remains an Android-only guarantee; iOS/macOS cover clean and
  foreground terminations plus the ringing-swipe case.

## Verification

Android and iOS/macOS verified by code review and linters (`trunk check` — no issues); a real Swift
compile needs the Flutter iOS/macOS build, and runtime verification is pending on real devices (not
emulators/simulators):

- **Android** — schedule an alarm, background then swipe the app away **without** the alarm ringing,
  and confirm the warning appears. Confirm the ringing-at-kill case still produces exactly one warning.
- **iOS/macOS** — schedule an alarm, then quit the app (macOS Cmd-Q; iOS a system/foreground
  termination) and confirm the warning appears once. Confirm normal backgrounding while an alarm is
  scheduled posts **no** warning (no resign-active spam). The suspended-swipe-kill case is expected to
  produce nothing (documented iOS limit).
