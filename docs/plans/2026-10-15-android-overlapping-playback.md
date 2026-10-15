# Android overlapping playback implementation

## Scope and ownership

Implement [issue #71](https://github.com/AndrewDongminYoo/warm_alarm/issues/71) and [its spec](../specs/2026-10-15-android-overlapping-playback.md) on `fix/android-overlapping-playback` in the main workspace.
The root owns `WarmAlarmForegroundService.kt`, a new `WarmAlarmForegroundServiceTest.kt` in the existing native unit-test directory, the Android README overlap contract, and these two documents.
Use the existing test dependencies and preserve generated files.

## Steps and verification

1. Add service-command regressions using platform mocks and observable pending callbacks → run `./gradlew :warm_alarm_android:testDebugUnitTest --tests '*WarmAlarmForegroundServiceTest' --console=plain` from the example Android host and observe intended lifecycle failures.
2. Clean up the current playback before replacing its ownership, and guarantee release after a stop exception → rerun the focused regressions.
3. Check the surrounding service behavior and all native unit tests → run `./gradlew :warm_alarm_android:testDebugUnitTest --console=plain`.
4. Check the Flutter workspace → run `flutter analyze --no-pub`, `dart run melos run test`, explicit read-only Dart formatting, scoped `trunk check`, and `git diff --check`.
5. Review the complete candidate, repair confirmed findings, commit by concern, and open a PR closing #71 → require current-head CI, Codex completion, an applicable CodeRabbit review or skip, and zero unresolved review threads.
6. Request operator merge after the terminal gates; merge, cleanup, and logging for this new PR require separate authorization.

## Limits

Use at most two local repair rounds and the public PR-loop budget of five hosted rounds within five hours, starting before the first hosted trigger.
Record test boundaries and actual results in the PR and Git-local task state.
