# macOS cancellation playback cleanup

## Contract

[Issue #73](https://github.com/AndrewDongminYoo/warm_alarm/issues/73) requires cancellation to stop an active macOS alarm before reporting success.
`cancelAlarm(id)` must stop the player only when its active alarm ID matches the cancelled ID.
`cancelAllAlarms()` must stop the active player regardless of its ID or whether its schedule remains in storage.
Both paths must clear ringing state before completion and reuse the existing audio cleanup that cancels fades and invalidates the volume timer.
Preserve notification ownership, pending-read ordering, unrelated playback, and the public API.
Cancellation does not acquire the notification-action semantics of `handleStop`, including its event and recurrence behavior.

## Verification

Use a silent audio fixture with looping enabled and assert that the real `AVAudioPlayer` is playing before cancellation.
Retain that player in the test and inspect its playback state in the cancellation completion, alongside the plugin's `isRinging` result.
Cover matching cancellation, a different alarm ID, all-alarm cancellation, and active playback whose schedule has already been removed.
Existing notification cancellation and foreground-delivery regressions must still pass.
Run macOS native tests, Dart tests, Flutter analysis, explicit formatting, and scoped Trunk checks.

## Boundaries

Do not change iOS, Android, generated wire code, dependencies, or release versions.
No device installation or visual approval is required.
Oracle returned `[no precedent found]` for the scoped macOS playback topics.
