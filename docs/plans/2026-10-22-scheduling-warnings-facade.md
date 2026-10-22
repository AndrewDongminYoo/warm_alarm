# Scheduling warning lists: facade stage

## Contract and scope

Complete the facade stage of [issue 122](https://github.com/AndrewDongminYoo/warm_alarm/issues/122) under the [approved contract](../specs/2026-10-17-scheduling-warnings-list.md).
The interface 0.1.8 is published and PR133 merged the three platform warning-list implementations.
At this stage's preflight, Android 0.1.6, iOS 0.1.13 and macOS 0.1.8 exact pub.dev endpoints returned 404.
Platform publication requires separate explicit approval before tags are pushed.
Do not raise the facade platform floors until their publication is verified.
The current explicit pr-loop invocation delegates implementation, commits, pushes, PR reviews and gated merge, but no package publication, branch cleanup or memory recording.

The facade already forwards the platform result and re-exports its public model; retain this implementation and prove it with contract tests.
Prepare facade 0.1.9, requiring interface ^0.1.8 and the three warning-list platform releases.
Keep the example screen as a legacy first-warning compatibility example; document that it cannot display simultaneous native diagnostics.
Update root and facade quick-start examples to iterate result.warnings.
No native, Pigeon, scheduling, audio, permission, persistence or rendered UI changes belong in this stage.

## Owned paths

- `warm_alarm/test/warm_alarm_test.dart` and `warm_alarm/lib/warm_alarm.dart` for facade coverage and API documentation.
- `warm_alarm/pubspec.yaml`, `warm_alarm/CHANGELOG.md`, and `warm_alarm/example/pubspec.yaml` for facade version and interface/platform floors.
- `README.md`, `warm_alarm/README.md`, `warm_alarm/example/README.md`, `warm_alarm_platform_interface/README.md`, and the three platform READMEs for accurate list examples and availability.
- This plan.

The root pubspec.lock is regenerated but remains ignored under the repository rule.
Applicable existing AGENTS.md and CLAUDE.md claims must be checked without unrelated edits.

## Steps and verification

1. Add zero, one and multiple-warning facade cases using only the facade import.
   Verify exact result identity, entry order/codes, legacy first/null getter, immutable snapshot and post-construction input mutation independence.
   Existing correct forwarding may already pass; do not invent a production regression.
   Challenge the new cases with a temporary isolated first-only forwarding mutation and restore it before final verification.
2. Prepare root/facade examples and correct the missed example-guide combined-message advice.
   Check every claimed symbol and behavior against current model/mapping/example source.
3. After approval, publish the three exact merged platform versions through existing package tag automation.
   Verify matching workflow success and exact hosted version metadata/source before raising facade floors.
   This is a publication prerequisite, not permission to publish the facade.
4. Set facade 0.1.9 and sibling floors, then run flutter pub get, affected facade/example tests, flutter analyze --no-pub, scoped 120-column dart format and Trunk checks.
   Native source is unchanged; avoid redundant local native builds.
   Hosted package checks and Pana must validate the actual candidate.
5. Review the actual diff at repository-required depth, fix findings, make one coherent feature commit, push and open a PR.
   Complete current-head reviews, security obligation, all applicable CI and full thread pagination before the delegated merge.
   Keep any unapproved publication or incomplete gate resumable rather than claiming completion.

## Precedent

Oracle returned workspace/federated release precedent from `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--memory.md`, linked to `raw/sources/.claude/projects/-Users-dongminyu-Development-01-personal-warm-alarm/memory/MEMORY.md` at source commit `c1681868ac634e4b2414874716bb75a7864113c4`, freshness unverified.
It confirms separate published-dependency verification beyond local workspace checks.
The explicit release order and exact floors come from current repository instructions and manifests, not the precedent's summary alone.
The scheduling-warning lookup returned [no precedent found]; the approved spec and current public model settle that behavior.
