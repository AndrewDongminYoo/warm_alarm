# iOS fallback replacement rollback

## Problem

Issue #88: a failed User Notifications replacement currently deletes the previous alarm and returns success with a warning.

## Contract

Snapshot the previous fallback schedule and exact pending requests before replacement.
Keep save-before-registration ordering so near-due notifications can find their generation.
Retain previous generated sound ownership until registration commits.
On failure, remove partial replacement requests, restore prior intent, and attempt every previous request, including weekly recurrence and active snooze.
Return `scheduling-failed` after successful recovery or `scheduling-rollback-failed` with both errors when recovery is incomplete.
A first-time failure leaves no saved alarm or partial request.
Hold the mutation queue through recovery and deliver one failure reply on the main thread, with one failed event and no scheduled event.
Keep unrelated pending notifications and existing AlarmKit cancellation and caller sound ownership contracts.
Commit a successful replacement and release only unreferenced previous generated sound files.

## Limits

Pending-request rollback cannot recall notifications already delivered during the attempt.
UserDefaults retains its existing non-throwing persistence model; this change does not add crash-atomic storage.
A native AlarmKit alarm already canceled by backend routing is not recreated by notification rollback.
Do not change public APIs, generated bindings, dependencies, release versions, Android, or macOS.
No visual approval is required for this native transaction change.

## Acceptance

Inject first and partial registration failures at the plugin notification boundary.
Compare encoded prior schedule data and exact request objects, content, and triggers after recovery.
Verify all recovery attempts despite an error, a queued mutation waiting for recovery, first-time failure, successful replacement, prior sound retention, and native backend cleanup.
Run existing iOS RunnerTests in CI because local disk pressure prevents a simulator build.
Observe the intended regression failure before implementation, then run the same suite after the fix.
