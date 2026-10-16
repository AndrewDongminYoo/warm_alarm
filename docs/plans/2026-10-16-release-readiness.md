# Documentation alignment and release readiness

## Scope and status

Prepare the next coordinated release from merged revision `97315fb021d83d3585a3b210add13281bd55e4e2`.
The operator authorized a documentation PR and a separate Android API 19–22 compatibility PR, including tests and reviews, after PR #93.
Scoped commits, pushes, PR creation, and review follow-through are authorized; merge, release tags, and package publication remain operator decisions.
This documentation PR leaves package versions and dependency constraints unchanged.
Do not describe the release as ready while the Android compatibility blocker below remains unresolved.

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

## Release blocker: Android API 19–22 scheduling

`warm_alarm_android/android/build.gradle` declares minSdkVersion 19.
The initial scheduling path and initialization recovery in `WarmAlarmPlugin.kt`, and boot recovery in `WarmAlarmBootReceiver.kt`, call `setExactAndAllowWhileIdle()` without an API 23 guard.
The [Android API reference](<https://developer.android.com/reference/android/app/AlarmManager#setExactAndAllowWhileIdle(int,%20long,%20android.app.PendingIntent)>) identifies that overload as available from API 23.
The existing `AlarmSchedulingBackend.scheduleLegacy()` calls `setExact()`, but its guarded dispatcher is used by rescheduling rather than those three entry points.
This is a source-confirmed compatibility gap, not a reproduced physical-device crash.

Recommended repair: preserve the declared minimum SDK and route initial scheduling, initialization recovery, and boot recovery through the existing version-aware scheduling policy.
Add regressions that execute those entry points on simulated API 19/22, API 23, and API 31 with exact-alarm access denied.
Verify `setExact()` below 23, the exact idle-capable API from 23, and the inexact fallback plus existing warning behavior on 31 when access is missing.
Run the Android native unit and instrumented jobs after the repair, with no permission or public API expansion.
The repair is approved as a separate native implementation PR and is not included in this documentation PR.
Do not hide the gap by silently raising minSdk.

## Ordered release steps

1. Review and commit the documentation reconciliation and Unreleased notes as one concern, then open its authorized documentation PR.
2. Resolve the Android blocker before any coordinated release tags.
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

The local [review receipt](/Users/dongminyu/Development/01_personal/pr-loop-reviews/warm_alarm/release-preparation-2026-10-16/REVIEW.md) retains the verification summary and review outcome outside Git-local control state.
Its adjacent evidence directory contains the [scoped Trunk output](/Users/dongminyu/Development/01_personal/pr-loop-reviews/warm_alarm/release-preparation-2026-10-16/evidence/docs-check.log) and [standalone validation results](/Users/dongminyu/Development/01_personal/pr-loop-reviews/warm_alarm/release-preparation-2026-10-16/evidence/standalone-validation-results.json), with per-package downgrade and test logs.
These are local operator artifacts, not files included in the repository or published packages.

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
