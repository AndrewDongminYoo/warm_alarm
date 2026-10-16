# macOS cancellation playback cleanup

## Contract

[Issue #73](https://github.com/AndrewDongminYoo/warm_alarm/issues/73) requires cancellation to stop an active macOS alarm before reporting success.
`cancelAlarm(id)` must stop the player only when its active alarm ID matches the cancelled ID.
`cancelAllAlarms()` must stop the active player regardless of its ID or whether its schedule remains in storage.
Both paths must clear ringing state before completion and reuse the existing audio cleanup that cancels fades and invalidates the volume timer.
Preserve notification ownership, pending-read ordering, unrelated playback, and the public API.
Cancellation does not acquire the notification-action semantics of `handleStop`, including its event and recurrence behavior.
Foreground schedule validation and player startup must be serialized with cancellation teardown, including the matching-ID check.
Cancellation must wait for an in-progress startup before reporting stopped playback.
Playback state reads and writes use the same delegate-owned lock; event emission and cancellation completion remain outside it.
Starting replacement playback must stop the previously tracked player so that cancellation cannot leave an untracked player ringing.

## Verification

Use a silent audio fixture with looping enabled and assert that the real `AVAudioPlayer` is playing before cancellation.
Retain that player in the test and inspect its playback state in the cancellation completion, alongside the plugin's `isRinging` result.
Cover matching cancellation, a different alarm ID, all-alarm cancellation, and active playback whose schedule has already been removed.
Existing notification cancellation and foreground-delivery regressions must still pass.
Pause the injected player factory after foreground validation, observe cancellation contending for the held playback lock, and assert that completion waits until startup is released and stopped.
Exercise this overlap for both cancellation APIs, then verify that cancellation before delivery suppresses playback entirely.
Retain both players during replacement and verify that cancelling the previous alarm leaves only the replacement playing.
Run macOS native tests, Dart tests, Flutter analysis, explicit formatting, and scoped Trunk checks.

## Boundaries

Do not change iOS, Android, generated wire code, dependencies, or release versions.
No device installation or visual approval is required.
Oracle returned `[no precedent found]` for the scoped macOS playback topics.
