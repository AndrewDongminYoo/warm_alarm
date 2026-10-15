# Android overlapping alarm playback

## Problem

[Issue #71](https://github.com/AndrewDongminYoo/warm_alarm/issues/71) identifies a leaked player when the foreground service receives another alarm while it is already playing.
The service replaces its current alarm and player without releasing the previous player, while old fade callbacks refer to the mutable player field.

## Contract

The foreground service owns one playback session at a time.
A newly fired alarm replaces the currently playing alarm, including a repeated fire for the same alarm ID.
Before it assigns the new schedule or starts playback, the service stops and releases the old player, cancels its fade and volume-enforcement callbacks, and stops its vibration.
Stopping the replacement leaves neither player's playback active.
Cleanup must attempt release even when stopping a player throws.
Android's [MediaPlayer resource guidance](https://developer.android.com/media/platform/mediaplayer/state-resources) requires releasing finished instances and documents state-dependent operation failures.
Replacement does not synthesize a user Stop or Snooze action, alter stored recurrence, or schedule a wake check for the replaced alarm.

## Non-goals

Do not add a queue, mixing, configurable overlap policies, dependencies, permissions, public APIs, or Pigeon changes.
Do not change Apple playback, stale notification-action handling, or volume restoration policy.

## Acceptance criteria

1. A native service regression starts looping alarms A and B through `onStartCommand`, stops B, and verifies that both players were stopped and released.
2. Replacement clears the first alarm's pending fade and volume-enforcement callbacks and cancels its vibration before the next playback starts.
3. A stop exception does not prevent release or replacement playback.
4. The tests fail on the unchanged service for the expected resource-lifecycle reason, then pass after the fix.
5. Android native unit tests, Flutter analysis and tests, scoped formatting, and Trunk checks pass.

## Constraints and precedent

Use the existing Android unit-test setup and mock only platform boundaries; the regression must execute the service's real command and playback logic.
These tests verify player and callback lifecycle calls, not physical speaker output.
Run heavy Android jobs sequentially on the local Mac.
There is no visual design change requiring operator approval.
Oracle returned `[no precedent found]` for this project's overlapping-alarm and playback-lifecycle topics; current source and the issue contract determine the change.
