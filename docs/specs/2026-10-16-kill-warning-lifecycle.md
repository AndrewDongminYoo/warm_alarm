# Kill-warning lifecycle documentation

## Problem

Issue #79 identifies documentation that treats warning configuration as immediate notification posting and clearing.
The native methods persist or remove warning text, while lifecycle callbacks submit notification requests separately.

## Scope

Correct the existing kill-warning API rows in the root, facade and platform-interface READMEs, and the Android, iOS and macOS kill-warning sections.
The extra root, interface and iOS corrections describe the same public contract and keep readers from receiving conflicting instructions.
No public API, native implementation, generated binding, dependency, permission, or notification behavior changes.

## Contract

- All platforms store title/body through setKillWarning and remove that configuration through clearKillWarning.
- Setting the warning does not immediately post a notification, and clearing the configuration does not remove a submitted or delivered warning.
- Android task-removal callbacks use configured text when a future alarm exists or an alarm is ringing; the warning enables auto-cancel and does not set the ongoing flag.
- macOS loss of active status submits a one-second request while the plugin reports a ringing alarm; its termination callback submits an immediate request for a future or ringing alarm.
- iOS app/scene deactivation submits a one-second request while plugin playback is active; its termination callback considers future process-owned alarms or active plugin playback, excluding future AlarmKit-managed alarms.
- Apple reactivation removes pending warning requests only, not delivered notifications; clearing configuration itself performs neither removal.
- Warning requests depend on the relevant lifecycle callback and notification permissions; documentation must not promise reliable interception of every force-stop or process kill.

## Acceptance

Each claim must map to the current set/clear implementation, lifecycle callback guard, or notification construction/removal call.
Preserve the iOS pending-slot reservation and configuration-failure descriptions.
Keep unrelated README issues outside this change.
Scoped Trunk checks, Flutter analysis and Dart format checks must pass.
Hosted CI and current-head code/security review must settle before requesting operator merge.
Content review is required; no UI or physical-device validation is claimed.
