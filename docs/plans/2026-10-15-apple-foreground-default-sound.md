# Apple foreground default sound implementation

## Contract and ownership

Implement [the approved issue contract](https://github.com/AndrewDongminYoo/warm_alarm/issues/70) and [the spec](../specs/2026-10-15-apple-foreground-default-sound.md) on `fix/apple-foreground-default-sound` in the main workspace.
The root owns both Apple `WarmAlarmDelegate.swift` files, their existing native test files, these two documents, and any strictly necessary native test fixture wiring.
The hosted-review repair also owns macOS `WarmAlarmStore.swift` and the schedule construction in `WarmAlarmPlugin.swift` to persist one notification generation per registration.
No dependency or generated-file changes are planned.

## Steps and checks

1. Add foreground delegate callback regressions with real schedule and notification content fixtures → verify the default-audio test fails because `.sound` is absent before changing behavior.
2. Select presentation options from the accepted schedule's audio source → verify default and empty sources request notification sound while custom sources do not.
3. Retain iOS occurrence rejection and duplicate suppression → verify native cancellation, replacement, and duplicate-delivery tests.
4. Run native checks sequentially → verify the macOS SwiftPM suite with the real FlutterMacOS framework and the iOS example `RunnerTests` target.
5. Verify the workspace → run `flutter analyze --no-pub`, `melos run test`, read-only 120-column Dart formatting, scoped `trunk check`, and `git diff --check`.
6. Check actual foreground delivery on macOS and the iOS simulator → record notification delivery and audio evidence separately from callback assertions; retain a named manual acceptance blocker if sound cannot be observed.
7. Review the complete candidate, commit by concern, push, and open a PR closing #70 → verify current-head CI, Codex, CodeRabbit, and all review threads under the PR-loop budget.
8. Request operator merge when the applicable gates pass; merge, branch cleanup, and memory recording are not delegated.

## Hosted-review repairs

Reject macOS deliveries after cancellation, validate the stored notification generation before foreground presentation, and exclude unrelated notification categories from alarm handling.
Use the same stored schedule object when constructing notification content.
Decode missing generation metadata as a legacy schedule and preserve it through snooze and recurrence copies.
Verify stale delivery and unrelated-category regressions fail before the fix, then run the full native suite and scoped project gates.

## Review limits

Use at most two local repair rounds for this bounded contract.
For hosted review, use five rounds and a five-hour deadline recorded before the first trigger.
The native tests inspect the options passed to the operating system and real playback state where applicable; they do not prove speaker output by themselves.
