# Alarm delivery and notification action safety

## Approved scope

Repair the reported release blockers in two concerns: Apple audio and action safety first, then notification category, title, and Android retention contracts.
Preserve public APIs and the declared platform minimum versions.
The existing Android compatibility PR already addresses the separate API 19–22 scheduling finding; verify its current evidence rather than repeat that change.

## Implementation and acceptance

1. Make Apple foreground custom-audio startup report its result, request notification sound after missing/corrupt assets or rejected playback, and expose custom playback failure.
   Verify missing file, corrupt file, missing asset, and rejected playback with native tests that first fail on the old behavior.
2. Scope Apple Stop/Snooze audio teardown to both alarm and occurrence.
   Verify an accepted action for A preserves B, and an older occurrence cannot stop the current occurrence of the same alarm.
3. Validate macOS action generation against the stored schedule, including default notification taps.
   Verify old Stop/Snooze/tap actions leave a replacement schedule and player intact.
   Retained consumed occurrences must preserve a later Snooze; a genuinely later recurring occurrence must still fire during a long Snooze.
4. Serialize macOS Snooze registration with schedule/cancel operations and commit storage and Snoozed only after add succeeds.
   Verify delayed completion, failed add with prior state preserved, and queued replacement/cancellation.
5. Merge Apple notification categories with host categories and honor distinct action-title pairs through owned category identifiers.
   Verify two alarms with different labels coexist and their responses still route to the plugin.
6. Detach the Android foreground notification on API 24+ when retention is requested and repost a normal notification below API 24.
   Verify stop and snooze with retention enabled and disabled at the compatibility boundaries.
7. Update the affected platform documentation and Unreleased notes, run scoped native tests, Flutter analysis/format checks, Trunk, and an adversarial review.

Minimum native checks: `bash tool/run_macos_native_tests.sh`, the example RunnerTests Xcode scheme, and `:warm_alarm_android:testDebugUnitTest` from the example Android host.
Run heavy native jobs sequentially.
Local Xcode rejects the example's iOS 13 deployment target, so record a test-only target override separately from the product support declaration.
Do not claim physical-device audibility from simulator or injected playback tests.

## Precedent and limits

Oracle retrieved `wiki/sources/warm_alarm--readme.md`, citing `warm_alarm/README.md`: platform limits and failures must remain observable, while Stop/Snooze events carry the alarm identity.
This confirms explicit failure reporting and scoped action ownership.
The retrieval returned no direct precedent for macOS occurrence ownership or snooze rollback; current source and native regressions decide those details.
The previously documented iOS fallback transaction remains in place.
