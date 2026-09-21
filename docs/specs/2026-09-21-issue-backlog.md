# Issues 14–21

## Scope

Resolve the acceptance criteria in GitHub issues #14 through #21 against the current implementation.
Readiness remediation and AlarmKit already have implementations, so assess their existing behavior before adding code.
Preserve the federated API, generated Pigeon boundary, and existing storage migrations.

## Contracts

- Readiness remediation returns the action status plus permission and readiness snapshots.
- Native lifecycle events enter a durable FIFO before dispatch and leave only after a successful Dart callback.
  The queue retains at most 64 events, drops the oldest when full, and removes corrupt records while preserving valid records.
  Delivery is at least once across a crash between callback completion and durable acknowledgement.
  The plugin cannot reconstruct callbacks the operating system never delivered.
- Android vibration follows alarm playback and stops with Stop, Snooze, failure, or service destruction.
- One-time schedules must be in the future at native millisecond precision.
  Recurring schedules use their local time and selected weekdays, so a past anchor remains valid.
- Fade timestamps must be nonnegative and strictly increasing at native millisecond precision.
- Both audio paths are permitted, with a nonempty `filePath` taking precedence over `assetPath`.
  Android may use the asset when credential-protected files are unavailable before unlock.
  System-managed AlarmKit audio retains its existing override semantics.
- Android storage recovery discards unreadable root data or individual records and writes the recoverable set through the existing persistence path.
- AlarmKit remains opt-in with User Notifications fallback and no claim of arbitrary Flutter full-screen UI.
- Custom Live Activities require explicit host setup and runtime authorization, with an unsupported result on other hosts.
  They do not require a push server or imply Android parity.

## Verification

Exercise facade rejection before dispatch, public fallback defaults, platform mapping, native event replay, corruption recovery, and vibration lifecycle.
Run native Android tests and Apple builds sequentially because this machine has limited memory.
Separate native build and mocked tests from actual device evidence for authorization, schedule, Stop, Snooze, and visible activities.

## Precedent

The Android permission callback must survive Activity configuration changes.
Reject duplicate requests and clear the callback only at a real Activity detach.
This confirms that event-delivery work must preserve the existing permission lifecycle.
Source: `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--android-permission-callback-lifecycle.md`.
Oracle returned no relevant precedent for the other scoped topics.

## Authority

The operator requested implementation of all eight issues with Sol/Terra parallel agents.
Local implementation and verification are authorized.
The operator subsequently invoked `pr-loop` and authorized scoped commits, pushes, PR creation, and hosted review replies.
Merge, issue closure, package publication, and installation on the operator's daily phone retain separate approval boundaries.
