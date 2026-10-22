# Scheduling warning lists: platform stage

## Contract and scope

Implement the platform stage of [#122](https://github.com/AndrewDongminYoo/warm_alarm/issues/122) under the [approved contract](../specs/2026-10-17-scheduling-warnings-list.md).
Interface 0.1.8 is published, including the legacy const constructor and the separate list snapshot constructor.
Android, iOS, and macOS must return every applicable warning without merging messages.
The public `warning` getter remains the first list entry or null.
The facade release remains a later stage after platform publication.

Owned changes are the three platform Pigeon schemas and their generated Dart/native pairs, native scheduling return paths, Dart result mappers, affected Dart/native tests, platform pubspecs/CHANGELOGs/READMEs, directly affected root/interface documentation, and this plan.
No permission, scheduling, audio, persistence, or UI behavior outside diagnostic results changes.
Use the current main workspace and sequential writers.

## Decisions and release boundary

Use a non-null private wire warning list.
Keep the Apple Dart wake-check warning first for legacy code compatibility, then preserve native warning order and null classification codes.
In iOS native scheduling, preserve configuration warning, runtime AlarmKit fallback warning, and capacity warning as separate entries when applicable.
No new warning code is introduced.
Prepare Android 0.1.6, iOS 0.1.13, and macOS 0.1.8, each requiring interface `^0.1.8`.
Tags and publication require separate approval after merge.
Do not raise facade floors until the platform versions exist on pub.dev.

## Steps and checks

1. Add regressions that exercise real Dart mappers with zero, one, and multiple native warnings and Apple wake-check composition.
   Observe the current merged-message behavior fail before changing the mapping.
2. Change upstream Pigeon schemas and run `dart run melos run generate`.
   Update native producers and their tests for list results; do not edit generated output directly.
   Add iOS scheduling regressions for separate native fallback/capacity warnings.
3. Map each warning into `WarmAlarmScheduleResult.withWarnings`, preserving detection order and the existing first-entry getter.
   Run the affected package suites and verify immutable snapshots.
4. Raise platform interface floors and prepare platform versions/CHANGELOGs.
   Run root `flutter pub get`; retain the ignored lockfile under repository policy.
   Correct affected existing documentation in this PR.
5. Run workspace Dart tests sequentially, `flutter analyze --no-pub`, scoped 120-column Dart format checks, and Trunk with explicit paths.
   Run native tests/builds sequentially when machine load permits; hosted platform jobs remain required.
   Android uses the declared Gradle unit-test job, macOS uses `bash tool/run_macos_native_tests.sh`, and iOS uses the app-hosted RunnerTests job.
6. Perform independent local review at the actual diff tier, repair confirmed findings, commit by concern, push, and open the PR.
   Complete current-head CI/Pana, hosted review, and full thread pagination before requesting operator merge.

## Precedent and verification limits

Oracle returned the federated-release precedent at `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--memory.md`, with source commit `c1681868ac634e4b2414874716bb75a7864113c4` and index freshness unverified.
It confirms interface publication before platform dependency changes and the need for published-dependency checks beyond workspace resolution.
The scheduling-warning query returned \[no precedent found\]; warning order follows the approved spec and existing legacy priority.
Dart mapping tests do not prove native scheduling, notification, or sound behavior.
Native scheduling tests and builds must cover the generated wire change.
No device install or launch is authorized by this task.
