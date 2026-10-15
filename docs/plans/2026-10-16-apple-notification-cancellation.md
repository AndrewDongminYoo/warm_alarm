# Apple notification cancellation implementation

## Scope

The operator explicitly requested the PR loop for issue #76.
Use the existing main workspace on `fix/apple-notification-cancellation` based on `de6991fa0fb8d75f1673a33cacfcb3b372050e4a`.
The root owns source edits, tests, staging, commits, and verification.
Owned paths are the iOS and macOS `WarmAlarmPlugin.swift` files, the existing iOS `WarmAlarmRequestRegistrationTests.swift`, a macOS cancellation test file, and these spec and plan documents.
Do not change dependencies, generated sources, release versions, or unrelated notification operations.

## Steps and checks

1. Add mixed-ownership native regression fixtures → observe the broad-removal behavior losing host requests before the fix.
2. Scope pending request removal by the existing category and exact kill-warning identifier → verify the original host requests remain and plugin requests disappear.
3. Cover asynchronous reads and AlarmKit failures → verify mutation ordering and preserved state on native cancellation errors.
4. Run incremental macOS SwiftPM tests with the real FlutterMacOS framework, iOS tests on hosted CI, Dart tests, Flutter analysis, explicit formatting, and scoped Trunk → inspect each result and its coverage.
5. Review both platform changes and their tests, repair verified findings, commit by concern, push, and open a PR closing #76 → observe current-head reviews and CI before requesting operator merge.

## Constraints

Run only one heavy mobile job at a time.
Preflight permits incremental macOS testing with the existing cache, but not a local iOS host rebuild at 97% Data-volume capacity.
A local executable Swift slice may establish the iOS cancellation regression before hosted tests; it does not replace the full native host check.
Allow two local repair rounds and five hosted rounds within five hours of the first hosted trigger.
Merge remains the operator's action; cleanup and recording for this new PR require their own request.
