# macOS host notification delegate plan

## Approved direction

Implement issue #75 through the requested PR loop in the existing workspace.
Personal account: `AndrewDongminYoo`.
Oracle retrieval returned `[no precedent found]`; the existing iOS forwarding implementation supplies the repository pattern.

## Owned paths

- macOS `WarmAlarmPlugin.swift` and a new `WarmAlarmNotificationCenterDelegate.swift`.
- Native `WarmAlarmNotificationCenterDelegateTests.swift`.
- `tool/run_macos_native_tests.sh`, `tool/macos_test_host.swift`, and `.github/workflows/macos_notification_delegate.yaml`.
- macOS README and AGENTS, this plan, and its matching spec.

## Steps

1. Add a real registration regression with a preinstalled host delegate, a minimal app-bundle XCTest runner, and validated decoded notification fixtures.
   Verify: the regression fails because the host callback is lost before the fix.
2. Install and retain a routing proxy and restore previous live delegates safely on plugin release.
   Verify: native callbacks reach only their intended recipient; asynchronous and fallback completion counts remain correct.
3. Cover repeated registration, release order, missing optional callbacks, nil settings notifications, and external delegate replacement.
   Verify: `bash tool/run_macos_native_tests.sh` runs all native tests with a nonzero executed count and zero failures.
4. Add a native CI job and affected documentation, then run Flutter checks and scoped Trunk checks.
   Verify: `flutter analyze --no-pub`, the macOS Dart test suite, explicit Dart formatting, and the non-Dart quality gate.
5. Review the final change, create semantic commits, open the PR, and verify current-head CI and hosted reviews.
   Stop for operator merge after the readiness gates pass.

The existing reusable workflow remains unchanged because its pin-update gate would require an unrelated major version upgrade.
Bare SwiftPM runs explicitly skip the nine application-only tests; the added app-host job rejects any skips.
