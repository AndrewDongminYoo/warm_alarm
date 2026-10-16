# Kill-warning lifecycle implementation plan

## Approved direction

Continue the operator-requested pr-loop with issue #79 as the sole open, unblocked issue.
The assigned workspace is the existing warm_alarm checkout; no worktree is needed.

## Steps and verification

1. Read the facade and interface APIs plus native set/clear and lifecycle handlers.
   Verify configuration changes separately from notification submission and removal.
2. Correct six existing README sections without changing executable behavior.
   Verify each statement against its native handler and retain iOS slot-limit details.
3. Run scoped Trunk formatting/checks, Flutter analysis and Dart formatting checks.
   Use a structured local review of the complete documentation diff and source-to-claim mapping.
4. Create one documentation commit and PR, then observe current-head CI and Codex code/security review.
   Stop for operator merge after the gates pass.

## Owned files

- README.md
- warm_alarm/README.md
- warm_alarm_platform_interface/README.md
- warm_alarm_android/README.md
- warm_alarm_ios/README.md
- warm_alarm_macos/README.md
- docs/specs/2026-10-16-kill-warning-lifecycle.md
- docs/plans/2026-10-16-kill-warning-lifecycle.md

## Evidence and limits

The current Android WarmAlarmPlugin, WarmAlarmKillWarningService and WarmAlarmForegroundService define configuration and task-removal behavior.
The iOS and macOS WarmAlarmPlugin files define lifecycle observers, warning requests and pending-only cancellation.
The initial README claims contradict those methods; this is the observed content failure.
No unit test will mirror prose, and no native runtime changes require device installation or a new behavior test.
Oracle returned no relevant precedent; its indexed source freshness was unverified.
The current source is the basis for the wording.
