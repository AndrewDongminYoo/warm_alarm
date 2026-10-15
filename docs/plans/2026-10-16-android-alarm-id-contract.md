# Android alarm ID implementation

## Ownership and approach

Implement [issue #72](https://github.com/AndrewDongminYoo/warm_alarm/issues/72) using [the signed 32-bit contract](../specs/2026-10-16-android-alarm-id-contract.md).
The root owns Android ID policy, the pending-intent factory, plugin scheduling/cancellation/recovery, receiver dispatch, foreground-service dispatch/actions, boot recovery, related tests, the Android README, and these documents.
Use the main workspace on `fix/android-alarm-id-contract`; preserve generated files and existing dependencies.
The operator approved the next issue's implementation and PR loop.
Advisor recommended a bounded ID contract because legacy out-of-range identities cannot be migrated independently of colliding supported IDs.

## Steps and checks

1. Add boundary, no-side-effect, and `-1` dispatch regressions against existing entry points → run focused Gradle unit tests and record expected failures.
2. Add shared ID validation, reject before public mutations, and guard delivery and recovery → run the new regressions and the full native unit suite.
3. Route boot restoration through the common factory and separate notification action identities → test real `PendingIntent` lookup and cancellation in the existing instrumented suite.
4. Document the Android range, failure behavior, and legacy limitations → check the README against the implemented paths.
5. Run `flutter analyze --no-pub`, Android Dart tests, explicit formatting, scoped Trunk, and `git diff --check` → require all relevant local gates to pass.
6. Run independent read-only lifecycle and test-fidelity reviews sized for the core change; repair confirmed contract failures → record the reviewed candidate and evidence.
7. Commit by concern, push, open a PR closing #72, and observe hosted review and CI → require the exact-head checks, Codex result, CodeRabbit review or explicit skip, and zero unresolved threads.
8. Request operator merge; cleanup and memory recording for the new PR remain separate requests.

## Resource and retry bounds

Native test command from the example Android host: `./gradlew :warm_alarm_android:testDebugUnitTest --console=plain --max-workers=2`.
The existing CI instrumented job runs `./gradlew :warm_alarm_android:connectedDebugAndroidTest --console=plain`.
Check load before each heavy local job and run only one at a time.
Allow two local repair rounds and five hosted rounds within five hours from the first hosted trigger.
