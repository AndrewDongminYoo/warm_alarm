# Scheduling warnings interface implementation

## Contract and scope

Implement the interface stage of [#122](https://github.com/AndrewDongminYoo/warm_alarm/issues/122) under the [approved warnings-list contract](../specs/2026-10-17-scheduling-warnings-list.md).
Keep the existing const constructor and optional `warning` argument compatible, add a read-only `warnings` list in detection order, and derive `warning` from its first entry or null.
Use `WarmAlarmScheduleResult.withWarnings` to copy a supplied warning list into a stable result while keeping the existing const constructor for a single optional warning.
Separate constructors prevent combining the single-warning and list arguments.
The operator approved proceeding with #122 on 2026-10-22.

The current branch already contains an uncommitted interface draft and model tests.
Preserve that work and complete it in the main workspace.
This stage owns the result model, its model tests, the interface README and CHANGELOG, and this plan.
No Pigeon schema changes are required for this interface stage.

## Steps and acceptance checks

1. Exercise zero, one, and multiple warnings, legacy constructor compatibility, detection order, null warning codes, and read-only results through the public package export.
   Verify with `flutter test --no-pub test/src/warm_alarm_schedule_result_test.dart --reporter expanded` from `warm_alarm_platform_interface`.
2. Verify that clearing or reusing the caller's warning accumulator cannot change either getter on a returned result.
   Observe the mutation regression fail before the fix, then pass after the new list constructor copies its input.
   Preserve the existing const constructor and its single-warning behavior.
3. Align the interface README and Unreleased notes with the model, explicitly distinguishing this API stage from the later platform migration.
   Review the root README, CLAUDE.md, and applicable AGENTS.md claims without changing release documentation for behavior that has not shipped.
4. Run the workspace Dart suites sequentially with `dart run melos exec --concurrency 1 --dir-exists=test --fail-fast -- "flutter test --no-pub --coverage --test-randomize-ordering-seed random --reporter expanded"`, and run `flutter analyze --no-pub` from the repository root.
   Check changed Dart files with `dart format --line-length 120 --output=none --set-exit-if-changed`, and run Trunk with the five owned paths explicitly listed.
5. Review the complete diff, including the untracked test and plan, for compatibility and missing contract coverage.
   Record the remaining publication prerequisite before proceeding to platform consumers.

## Release boundary and precedent

Merge and publish the interface before a separate platform stage raises its interface dependency floor and implements native warning lists.
Publish the three platform packages before the facade stage raises its floors.
Local workspace resolution does not verify published sibling dependency constraints.

Oracle returned the federated-release precedent at `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--memory.md`, sourced from `raw/sources/.claude/projects/-Users-dongminyu-Development-01-personal-warm-alarm/memory/MEMORY.md`, at source commit `c1681868ac634e4b2414874716bb75a7864113c4` with current index freshness unverified.
It confirms the separate interface-first release stages already required by AGENTS.md and the approved spec.
The scheduling-warning and constructor compatibility query returned \[no precedent found\]; those choices follow the approved spec and current model compatibility requirements.
Oracle's general API-preservation precedent at `wiki/sources/claude--claude.md` confirms retaining the existing const constructor while adding the separate snapshot constructor.
