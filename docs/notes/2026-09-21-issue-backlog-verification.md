# Issues 14–21 verification

## Delivery state

This record captures implementation and local review before PR publication.
The operator subsequently authorized scoped commits, pushes, and PR review through `pr-loop`.
Current remote check and review results belong to the PR and Git-local loop state.
No GitHub issue has been closed during this task.
The operator's physical iPhone has not been installed, launched, or otherwise changed.

| Issue | Change or assessment                                                                                                            | Evidence and remaining acceptance                                                                                                                                                            |
| ----- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| #14   | Retained the existing readiness remediation API and platform behavior                                                           | Existing Dart and native regression suites pass; no duplicate implementation added                                                                                                           |
| #15   | Durable bounded native event queues, callback acknowledgements, replay, corruption recovery, and early Dart listener buffering  | Native tests cover persistence, replay, failed callbacks, failed acknowledgement writes, overflow, and valid neighbors of corrupt records; Dart platform tests cover initialization delivery |
| #16   | Android vibration follows playback and stops during teardown                                                                    | Vibration controller and audio policy tests pass                                                                                                                                             |
| #17   | Reject past one-time alarms and invalid fade timestamps before platform dispatch                                                | Facade tests cover past one-time schedules, recurring anchors, negative timestamps, ordering, and millisecond collisions                                                                     |
| #18   | Recover readable Android schedules from corrupt persisted data                                                                  | Store tests cover invalid roots and mixed valid/invalid entries                                                                                                                              |
| #19   | Match AlarmKit capabilities to actual authorization; require both Live Activity host flags for Snooze countdown configuration   | Native regression suite passes; final-build physical-device schedule, Stop, and Snooze acceptance remains pending                                                                            |
| #20   | Define source precedence and platform audio limits; repair Android loop/volume behavior and share tested Apple source selection | Audio policy/source tests and documentation updated; physical audio and vibration behavior was not exercised in this task                                                                    |
| #21   | Public start/update/end API, unsupported defaults, opt-in iOS routing, local ActivityKit adapter, and accessible Widget sample  | Dart mappings, native controller tests, and real-SDK sample type checks pass; a configured host's actual ActivityKit lifecycle and rendered Widget acceptance remain pending                 |

The queues acknowledge Dart callback delivery, not downstream application processing.
Apple queue writes use atomic file replacement; the tests establish persistence across storage recreation, not a power-loss durability guarantee.
Queues retain at most 64 records and can replay an acknowledged callback if the process exits before acknowledgement persistence.

## Verification results

Each test suite reads implementation behavior within its test boundary.
None of these unit suites proves physical alarm presentation, sound, haptics, or Widget rendering.

| Check                                | Result                                                                             | Evidence                                                                                          |
| ------------------------------------ | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Sequential workspace Flutter tests   | 243 passed across seven packages                                                   | `/tmp/warm-alarm-dart-final.log`                                                                  |
| Android native unit tests            | 51 passed, zero failures/errors/skips                                              | `/tmp/warm-alarm-android-final.log` and example build JUnit XML                                   |
| iOS RunnerTests                      | 246 passed, zero failed/skipped                                                    | `/tmp/warm-alarm-backlog-final.xcresult`; `xcresulttool get test-results summary`                 |
| macOS native package tests           | 15 passed                                                                          | `/tmp/warm-alarm-macos-final.log`                                                                 |
| Flutter analysis                     | No issues                                                                          | `/tmp/warm-alarm-analyze-final.log`                                                               |
| Scoped Dart formatting               | 21 files checked, zero changes                                                     | `dart format --line-length 120 --output=none --set-exit-if-changed` on changed and new Dart paths |
| Live Activity host and Widget source | Both Swift 6 type checks passed against the actual iOS SDK and built plugin module | Separate app and Widget compilation boundaries; no Flutter dependency in the Widget               |

The Flutter suite included `check_readiness` 6, facade 40, Android 54, example 9, iOS 47, macOS 38, and platform interface 49 tests.
The iOS run used an iOS 26.5 simulator and a command-only `IPHONEOS_DEPLOYMENT_TARGET=15.0` override because the installed Xcode SDK rejected the example's older deployment target.
This does not establish compatibility with the oldest supported iOS deployment target.
The run emitted existing deprecated API and XCTest deployment-target linker warnings; the result bundle reports no test runtime warnings.

The Android scalar-corruption regression was verified red by temporarily removing per-record decoding recovery, then green after restoring it.
The Pigeon whitespace normalizer refused a non-generated fixture before accepting a generated fixture.
A temporary unknown-word canary caused the spelling gate to fail, and the original README bytes were restored afterward.

## Reproduction

Run the Dart suite and analysis from the repository root.

```bash
melos exec --concurrency=1 --dir-exists=test --fail-fast -- "flutter test --concurrency 2 --test-randomize-ordering-seed random"
flutter analyze --no-pub
trunk check --no-fix --jobs 2
git diff --check
```

Run native jobs sequentially and check machine load first.
The Android native task is `./gradlew :warm_alarm_android:testDebugUnitTest --console=plain` from `warm_alarm/example/android`.
The iOS native suite is the example Runner scheme's `RunnerTests` target.
The macOS package tests require the Flutter SDK's real `FlutterMacOS` framework search and runtime paths when invoked with `swift test` outside Xcode.

Regenerate the Pigeon outputs with `melos run generate`.
The schemas use Pigeon 29's callback annotation to preserve the existing callback protocol.
The generation command applies a guarded trailing-whitespace normalizer instead of hand-editing generated files.

## Review and precedent

Sol and Terra workers implemented independent scopes and reviewed Android, Apple, and public API behavior.
Repairs include per-record event decoding, durable Apple queue storage, acknowledgement-write failure replay, correct AlarmKit authorization reporting, ActivityKit sample imports, and immutable alarm identity validation during recovered updates.

The Oracle precedent requires Android notification permission callbacks to survive Activity configuration changes and rejects overlapping requests.
This confirmed preservation of the existing permission lifecycle during event-delivery changes.
Source: `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--android-permission-callback-lifecycle.md`.
For the other queried topics: \[no precedent found\].

## Next acceptance and authority

For #19, use a configured AlarmKit host on a supported physical iPhone and verify scheduling, native Stop, and Snooze on the final build.
Earlier evidence in PR #50 does not cover final-build Stop acceptance.
For #21, build the app and Widget targets described in `warm_alarm_ios/example/live_activity/README.md`, then verify start, visible update, end, disabled authorization, and accessibility in the rendered presentations.
The repository's general Flutter example does not yet embed this optional Widget sample.

Physical-phone installation or launch requires explicit action-specific operator approval.
The authorized PR loop covers scoped commits, pushes, PR creation, and review replies.
Merge, issue closure, package publication, cleanup, and memory recording have not been authorized.
Future publication must preserve the existing interface → platform packages → facade release order and raise sibling constraints to the releases that supply new APIs.

## Hosted review follow-up

PR #56 is a draft while the required federated release sequence and final device acceptance remain incomplete.
The first hosted run exposed missing facade forwarding coverage and an optimized iOS test binding collision.
The repair adds direct forwarding/error coverage and removes unnecessary binding initialization from the new Live Activity tests while preserving the existing custom-binding regression.
The repaired Dart suite passed 248 tests; the optimized facade and iOS runs passed 43 and 49 tests respectively, each with 100% reported coverage.
Flutter analysis passed after the repairs.

The first hosted Pana checks failed for the facade and iOS package because the published interface 0.1.3 does not contain the new Live Activity contract.
A separate interface 0.1.4 prerequisite PR is required before dependent package lower bounds can be raised.
No Pana threshold was relaxed, and no release was published.
The release precedent confirmed this ordering: `/Users/dongminyu/.claude/projects/-Users-dongminyu-Development-01-personal-warm-alarm/memory/federated-release-order.md`.

Hosted review also identified a race between reading an empty event queue and becoming idle.
Independent Sol review extended the repair to preserve a drain request that arrives before a failed callback or failed acknowledgement write.
Regression fixtures reproduced the empty-read failure on Android, iOS, and macOS.
The two additional failure-path fixtures failed on the original macOS implementation with the expected missing retry before the production repair.
The macOS package policy now explicitly permits native persistence, acknowledgement, replay, and audio-source tests while retaining Dart wire-mapping coverage.
The advisory Codex doctor run after that policy update reported one warning and zero failures; the warning concerned rollout inventory and is unrelated to the package behavior.

The final queue repair passed Android 54, iOS 249, and macOS 18 native tests with zero failures or skips.
Android evidence is `/tmp/warm-alarm-android-queue-race-green.log` and the JUnit XML; iOS evidence is `/tmp/warm-alarm-pr56-queue-final.xcresult`; macOS evidence is `/tmp/warm-alarm-macos-queue-race-green.log`.
The final Sol review found no remaining defect in the six queue files or Apple delegate/plugin integration.
The seven changed queue/evidence files passed scoped Trunk checks.

## Release-stage update on 2026-09-22

The preceding sections are historical checkpoints and are superseded by this release-stage update where they describe pending platform publication or the missing example Widget.
PR #57 published interface 0.1.4.
PR #58 merged as `af9a950117f6de0016092eb38975b0ff7efa7279` and published Android 0.1.3, iOS 0.1.10, and macOS 0.1.3 through successful runs 35684963547, 35684963489, and 35684963588.
The pub.dev version endpoints confirm all three versions and their interface `^0.1.4` dependency.

The configured example now embeds the Widget and package-local Swift sources.
Simulator checks covered start, updates, end, unknown identifiers, permission-disabled rejection, and permission restoration.
The operator approved the scheduled, ringing, and snoozed presentation, and that approval carried to the final platform head because visual inputs remained equivalent.
The final platform head passed 249 iOS native tests and 18 macOS native tests; its Apple Dart acknowledgement repair passed 93 Dart tests.
A native callback now stays pending while the Dart stream has no listener, including after the last listener cancels.

PR #56 now carries the remaining facade forwarding, schedule validation, dependency floors, and contract documentation.
No physical phone was changed; issue #19 final-build Schedule, Stop, and Snooze acceptance remains pending.
No issue has been closed, and cleanup and durable memory recording were not requested.
