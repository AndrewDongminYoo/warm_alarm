# Documentation alignment and release readiness

## Scope and status

Prepare the next coordinated release from merged revision `97315fb021d83d3585a3b210add13281bd55e4e2`.
The operator authorized a documentation PR and a separate Android API 19–22 compatibility PR, including tests and reviews, after PR #93.
Scoped commits, pushes, PR creation, and review follow-through are authorized; merge, release tags, and package publication remain operator decisions.
The documentation and compatibility PRs leave package versions and dependency constraints unchanged.
The Android repair below must pass its tests and reviews and receive operator merge approval before release preparation advances to version assignment.

## Documentation contract

Current READMEs must match public method signatures, exported model fields, enum values, event payloads, platform behavior, and actual CI triggers.
Keep released CHANGELOG sections unchanged and collect new changes under Unreleased until each package's release stage is approved.
Historical design documents and verification notes describe their dated revisions, not the current runtime contract.
The source and current package manifests take precedence for new release preparation.

## Published baseline and proposed versions

The pub.dev package APIs and matching local tags were checked on 2026-10-16.
All five current pubspec versions equal their latest published versions.
These are proposed patch releases, not assigned or published versions.
Re-query pub.dev before each version edit to detect another publisher's work.

| Stage | Package                       | Published/current | Proposed | Dependency floor for that stage                             |
| ----- | ----------------------------- | ----------------- | -------- | ----------------------------------------------------------- |
| 1     | warm_alarm_platform_interface | 0.1.6             | 0.1.7    | No new sibling dependency                                   |
| 2     | warm_alarm_android            | 0.1.4             | 0.1.5    | warm_alarm_platform_interface ^0.1.7                        |
| 2     | warm_alarm_ios                | 0.1.11            | 0.1.12   | warm_alarm_platform_interface ^0.1.7                        |
| 2     | warm_alarm_macos              | 0.1.5             | 0.1.6    | warm_alarm_platform_interface ^0.1.7                        |
| 3     | warm_alarm                    | 0.1.7             | 0.1.8    | interface ^0.1.7, Android ^0.1.5, iOS ^0.1.12, macOS ^0.1.6 |

The interface release contains documentation corrections, with no new runtime API since 0.1.6.
The proposed platform floor adopts that coordinated documentation baseline; existing runtime warning APIs already exist in interface 0.1.5.
The facade floor must include the new platform releases to guarantee the native fixes rather than allowing their older published versions.
Do not combine an unpublished platform floor with its facade release in one stage.

Sources: [interface](https://pub.dev/api/packages/warm_alarm_platform_interface), [Android](https://pub.dev/api/packages/warm_alarm_android), [iOS](https://pub.dev/api/packages/warm_alarm_ios), [macOS](https://pub.dev/api/packages/warm_alarm_macos), and [facade](https://pub.dev/api/packages/warm_alarm).

## Android API 19–22 scheduling repair

`warm_alarm_android/android/build.gradle` declares minSdkVersion 19.
At the preparation baseline, the initial scheduling path and initialization recovery in `WarmAlarmPlugin.kt`, and boot recovery in `WarmAlarmBootReceiver.kt`, called `setExactAndAllowWhileIdle()` without an API 23 guard.
The [Android API reference](<https://developer.android.com/reference/android/app/AlarmManager#setExactAndAllowWhileIdle(int,%20long,%20android.app.PendingIntent)>) identifies that overload as available from API 23.
The existing `AlarmSchedulingBackend.scheduleLegacy()` calls `setExact()`, and the compatibility repair routes those three entry points through its version-aware dispatcher.
The initial schedule result uses the dispatcher's actual inexact-selection result for its warning and readiness decision.
The declared minimum SDK, permissions, public API, and regular PendingIntent identity remain unchanged.

`WarmAlarmSchedulingTest` calls the actual entry points with simulated API 19/22, API 23, and API 31 with and without exact-alarm access.
Its assertions read the AlarmManager method, alarm type, fire time, PendingIntent, persisted schedule, scheduled event, and result warning.
The active-snooze fixture verifies that the store can read its snooze deadline before invoking recovery.
The corrected fixtures reproduced seven legacy-path failures before the implementation changed; the modern-path cases passed.
These JVM checks verify platform API selection, not physical-device delivery.
The full native unit suite and the Android instrumented job remain required for the final candidate.
The repair is tracked separately in [PR #95](https://github.com/AndrewDongminYoo/warm_alarm/pull/95), stacked on [documentation PR #94](https://github.com/AndrewDongminYoo/warm_alarm/pull/94).

## Approved release follow-ups

The operator also authorized the reported wake-check compatibility repair, legacy Android runtime checks, and bounded Gradle warning cleanup before release.
Wake-check registration keeps its inexact behavior with `set()` below API 23.
The same service used API 21 audio attributes without a guard; API 19–20 now uses the alarm stream instead.
The regression fixtures reproduce both failures before those changes and retain the modern branches.
The JVM suite runs interpreted because its SDK fixtures temporarily replace a static final Android stub field; JIT constant folding otherwise retains a previous case's SDK value.

The example Gradle wrapper is regenerated at 9.2.1, whose embedded Kotlin version matches the Flutter Gradle plugin's 2.2.20 request.
This removes the Gradle 9.0 support warning and the embedded-Kotlin mismatch.
The example uses the current Kotlin compiler-options DSL while retaining its JVM 11 target.
Sources: [Gradle compatibility table](https://docs.gradle.org/current/userguide/compatibility.html) and [Gradle 9.2.1 release notes](https://docs.gradle.org/9.2.1/release-notes.html).
The operator subsequently approved upgrading the example host to AGP 9.0.1 and Kotlin 2.3.20 in the same compatibility PR.
Its checked-in `android.newDsl=false` and `android.builtInKotlin=false` settings retain the Flutter legacy DSL and external Kotlin plugin integration for direct Gradle CI jobs.
The public plugin keeps its existing Flutter constraint and Kotlin plugin application.
AGP 9 reports deprecation notices for these compatibility settings and the existing Jetifier setting; this migration removes Flutter version recommendations, not every build warning.
Sources: [Flutter AGP migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin) and [AGP 9.0 compatibility](https://developer.android.com/build/releases/agp-9-0-0-release-notes).
The migration must remove both Flutter version recommendations, pass the native unit suite, build the example and instrumented APKs, and pass the API 19/22/29 hosted execution matrix.
The scoped AGP migration and Kotlin compatibility Oracle queries returned \[no precedent found\].

The boot receiver accepts `LOCKED_BOOT_COMPLETED` only from API 24 and rejects it before accessing storage on API 19–23.
Ordinary boot recovery remains supported on those older versions.
Regression cases cover the rejected legacy actions and the API 24 direct-boot boundary.

The native instrumentation matrix targets API 19, 22, and 29.
Its test-only `targetSdk` is explicitly 19 to preserve the pre-migration test APK contract; AGP 9 otherwise changes the resolved target to compileSdk 34.
The example host retains Flutter's target SDK, and the plugin does not set a consuming app's target SDK.
Its delivery fixture writes a silent WAV, registers through the production scheduler, waits for the persisted fired event and service startup, checks for audio initialization failure, sends Stop, and waits for the wake-check event.
It removes its own alarms, notification, events, and audio file after execution.
The test runtime excludes the Flutter embedding's transitive `androidx.exifinterface` dependency, which declares API 21, because this native fixture never starts the Flutter engine or decodes images.
The manifest no longer overrides dependency minimum SDK declarations.
This is a native plugin check, not proof of current Flutter engine compatibility with API 19.
Hosted results must pass before the candidate is ready.

Oracle's `wiki/concepts/federated-pub-package-release-chain.md`, sourced from `raw/sources/warm_alarm/AGENTS.md`, confirms the declared API 19 floor and supports repairing rather than silently raising it.
`wiki/concepts/mac-mini-resource-limits.md`, sourced from `raw/sources/.claude/rules/mac-mini-resource-limits.md`, confirms serial local mobile builds and hosted emulator execution.
The direct wake-check and Gradle-warning queries returned \[no precedent found\].

## Ordered release steps

1. Review and commit the documentation reconciliation and Unreleased notes as one concern, then open its authorized documentation PR.
2. Verify and obtain operator merge approval for the Android compatibility repair before any coordinated release tags.
3. For stage 1, assign interface 0.1.7 and replace only its Unreleased heading with that version.
   Resolve the workspace with `flutter pub get`, run package tests, scoped formatting and Trunk, and complete the interface Pana job.
   Complete PR review, obtain operator merge, verify the merge, and then obtain or reuse explicit tag/publication authority.
4. Confirm interface 0.1.7 exists on pub.dev before changing the three platform versions and their interface floors.
   Convert only their Unreleased sections, run the stage's Dart and native checks, and complete Pana against the published interface.
   Merge and publish the three matching package tags only under explicit authority.
5. Confirm all three platform versions exist on pub.dev before preparing facade 0.1.8 and its dependency floors.
   Update installation snippets in the root and facade READMEs when the facade version is assigned.
   Convert its Unreleased section, then run facade/example tests and Pana before the final merge and publication.
6. For each stage, run `flutter pub publish --dry-run` in the package after its version and dependencies are assigned.
   Treat that result as packaging evidence, not evidence that publication happened.
   Use the publish workflow result and exact pub.dev version response to verify publication.

The repository ignores pubspec.lock, so resolve it locally without committing it.
The tag must be `<package_name>-v<version>` and match the package's pubspec version.
The existing `.github/workflows/publish.yml` declares a separate OIDC publish job for each package.
Each package's private pub.dev automated-publishing setting still needs confirmation at release time; public version metadata does not prove that setting is currently valid.

## Validation and limits

The local review receipt at `/Users/dongminyu/Development/01_personal/pr-loop-reviews/warm_alarm/release-preparation-2026-10-16/REVIEW.md` retains the verification summary and review outcome outside Git-local control state.
Its adjacent `evidence/` directory contains `docs-check.log`, `standalone-validation-results.json`, and per-package downgrade and test logs.
These are local operator paths, not GitHub links or files included in the repository or published packages.

Current-bound checks used isolated copies of the five packages with only `resolution: workspace` removed from their copied manifests.
`flutter pub downgrade --no-example` resolved every sibling dependency from hosted pub.dev packages rather than the local workspace.
All five isolated package Dart test suites passed with those resolved lower bounds.
These checks cover current constraints and Dart behavior, not the proposed unpublished versions or native runtime behavior.
Pana is not installed locally; its declared CI invocation remains a required stage gate:

```bash
pana <package> --project-root . --no-warning
```

Keep the project root for the existing Pana workflow and verify hosted dependency resolution separately; a workspace score alone does not prove that a published consumer can resolve the new floors.
After each stage's dependencies exist, repeat an isolated consumer/package resolution check against those published versions.

Android/iOS Fluttium E2E jobs in `.github/workflows/warm_alarm.yaml` run only for workflow_dispatch or v-prefixed tags.
Package publication tags such as warm_alarm-v0.1.8 do not trigger that E2E condition.
Request an explicit workflow_dispatch run for release acceptance rather than treating skipped E2E jobs as passes.
macOS readiness is a separate manual Fluttium check.
Native macOS tests and host builds do not substitute for that UI flow.
No physical phone install, launch, notification delivery, AlarmKit interaction, or Live Activity visual approval was performed during documentation preparation.

## Precedent

Oracle returned the personal warm_alarm federated-release precedent through `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--memory.md`, with provider provenance `c1681868ac634e4b2414874716bb75a7864113c4` and unverified index freshness.
The linked local `federated-release-order.md` was read and compared with the current workspace and publish workflow.
Its workspace-resolution failure and three-stage publication lesson confirm the separated release stages and the additional hosted lower-bound checks above.
No applicable documentation-drift precedent was returned.
The separate `legacy scheduling` and `alarm recovery` queries returned no relevant precedent; the compatibility repair follows current source and failing regression evidence.
