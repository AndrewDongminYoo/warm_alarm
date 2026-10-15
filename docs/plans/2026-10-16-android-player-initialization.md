# Android player initialization correction

## Scope

Carry the operator-approved correction through a PR using [the initialization cleanup contract](../specs/2026-10-16-android-player-initialization.md).
Reuse the implementation and verification completed before the operator invoked the PR loop.
The root owns the foreground service, its existing native test file, and these two documents on `fix/android-player-initialization` in the main workspace.

## Execution and verification

1. Add failure injection to the existing service harness and regress data-source, preparation, start, and cleanup failures → the focused Gradle test must fail at missing release on the unchanged implementation.
2. Release the local player when initialization throws and rethrow the original exception → the new cases and existing successful playback cases must pass.
3. Verify the relevant surface → run `./gradlew :warm_alarm_android:testDebugUnitTest --console=plain --max-workers=2` from `warm_alarm/example/android`, Android package `flutter test --no-pub`, root `flutter analyze --no-pub`, explicit formatting checks, and scoped Trunk checks.
4. Review the complete candidate for ownership transfer, invalid-state cleanup, original-error preservation, and test fidelity → record findings and verification evidence in Git-local loop state.
5. Commit the cohesive fix, tests, and contract; push and open a PR → require current-head CI, Codex completion, an applicable CodeRabbit review or explicit skip, and zero unresolved review threads.
6. Request operator merge → cleanup and memory recording for this new PR remain separately authorized actions.

## Boundaries

Run heavy native jobs sequentially after checking machine load.
Use at most two local repair rounds and five hosted rounds within five hours, with the hosted budget recorded before publication.
Do not expand this correction into the next ID-collision issue.
