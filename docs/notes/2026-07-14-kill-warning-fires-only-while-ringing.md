# Kill-Warning Fires Only While Ringing (should fire while an alarm is scheduled)

**Date:** 2026-07-14
**Status:** Known gap — not yet fixed. Raised from the consuming app (WarmWake) during
warm_alarm integration review.

## Problem

`setKillWarning(title:body:)` stores a title/body that the OS is meant to show if the user force-quits the app while an alarm could still fire. This supersets the `alarm` package's `setWarningNotificationOnKill` + per-alarm `warningNotificationOnKill` flag, whose purpose is to warn the user when they swipe the app away **while an alarm is scheduled** — the dominant failure mode on aggressive OEMs, where a swiped-away app never wakes to ring.

The current native implementation fires the warning **only when an alarm is actively ringing at kill time**, which is a much narrower case than intended. If the user schedules an alarm for 07:00 and swipes the app away at 23:00, no warning is posted — exactly the situation the feature exists to cover.

## Current behavior (all three platforms share the same narrow guard)

- **iOS** — `WarmAlarmPlugin.postKillWarningIfNeeded()` guards `delegate.currentlyPlayingAlarmId != nil`. Fires only if an alarm is ringing.
- **macOS** — same guard `currentlyPlayingAlarmId != nil`.
- **Android** — the warning is posted from `WarmAlarmForegroundService.onTaskRemoved` behind `if (isRinging)`. The foreground service only runs while an alarm is ringing, so `onTaskRemoved` cannot fire for a merely-scheduled alarm — the swipe-away-while-scheduled case produces no warning at all.

## Intended behavior (parity with the `alarm` package)

Post the kill warning when the app is force-quit **and at least one future alarm is scheduled** (whether or not it is currently ringing). Ringing is a strict subset of "scheduled," so broadening the guard preserves the current case and adds the missing one.

## Proposed fix (per platform)

- **iOS / macOS** — change the guard in `postKillWarningIfNeeded()` from `currentlyPlayingAlarmId != nil` to "a future alarm exists": read `WarmAlarmStore`, filter `scheduledAtMillis > now` (same predicate `init()` already uses), and post if non-empty **or** an alarm is ringing. The lifecycle hook that calls `postKillWarningIfNeeded()` (scene/app termination) already exists.
- **Android** — `onTaskRemoved` in the foreground service is the wrong (too-late) hook because no service runs while merely scheduled. Post the warning from an app-level `Service.onTaskRemoved` (or an `ActivityLifecycle`/`ComponentCallbacks` path) that is alive regardless of ringing state, gated on `WarmAlarmStore` having a future alarm.

## Verification

Not implemented. When fixed, verify on a real device (not just emulator): schedule an alarm, background then swipe the app away **without** the alarm ringing, and confirm the warning notification appears. The ringing-at-kill case must keep working.
