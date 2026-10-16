# macOS cancellation playback implementation

## Scope and authority

The operator requested the next issue through `pr-loop`.
Issue #73 is an open P1 defect confirmed in the current cancellation paths.
Use the main workspace on `fix/macos-cancellation-playback`, based on merge commit `6e83ee43b620f5bda1bfd9588e7866a9f0d3a713`.
The root owns the macOS `WarmAlarmPlugin.swift`, `WarmAlarmDelegate.swift`, `WarmAlarmCancellationTests.swift`, and these two documents.
Keep the prior branch intact because cleanup was not requested.

## Steps

1. Extend native cancellation tests with a real silent looping player and a read-only internal player reference → observe playback and ringing assertions fail before the fix.
2. Add matching-ID and all-player cleanup methods using the existing delegate teardown, then call them from cancellation → verify stop-before-completion and unrelated playback preservation.
3. Run the full macOS native suite with the real FlutterMacOS framework, macOS Dart tests, Flutter analysis, explicit Dart formatting, and scoped Trunk → inspect results and test coverage.
4. Review the complete diff against the cancellation contract → repair confirmed findings within two local rounds.
5. Commit, push, and open a PR closing #73 → observe exact-head CI and hosted reviews within five rounds and five hours.

## Completion boundary

Merge remains the operator's action.
Cleanup and memory recording for this PR were not requested.
Run at most one heavy mobile job at a time and check load before native testing.
