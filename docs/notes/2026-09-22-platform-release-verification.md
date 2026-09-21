# Platform release verification

## Release boundary

PR #57 merged as `b61b5c405a25db8c289fec233d8a417506a0220e`.
The release tag `warm_alarm_platform_interface-v0.1.4` points to that commit.
GitHub publish run `35658336292` succeeded, and the pub.dev version endpoint confirms interface 0.1.4 with archive SHA-256 `42487fd7c26589e9b27439197b6c50c6a9727eb6f98fcaa388a7ec9e1f3b84c5`.
The platform stage prepares Android 0.1.3, iOS 0.1.10, and macOS 0.1.3 with interface `^0.1.4`.
No platform release has been published during this stage.

## Code and native boundaries

The six regenerated Pigeon outputs and 33 native implementation files match the reviewed integrated implementation at `9bcddb51267aca7074312e372602cfb59244e4ab`.
The facade library and its package manifest are unchanged from the merged base.
Native queue tests previously passed 54 Android, 249 iOS, and 18 macOS cases on that integrated implementation; source parity permits reuse of that implementation evidence but does not replace current-head hosted checks.

The new macOS workflow executes native tests after the example host build.
Its exact framework-discovery and SwiftPM command passed 18 tests locally with zero failures.
Evidence: `/tmp/warm-alarm-platform-macos-ci-command.log`.

## Dart and static checks

The platform-only workspace passed 240 Flutter tests across seven packages: 6, 35, 54, 9, 49, 38, and 49 tests respectively.
The difference from the integrated branch is the facade work reserved for the next release stage.
Evidence: `/tmp/warm-alarm-platform-stage-tests.log`.
The configured fixture subsequently passed all nine existing example tests, and workspace analysis passed after the fixture was added.
Eleven changed hand-written Dart files passed the 120-column format check without changes.

An intentionally missing Widget target caused the Xcode structure validator to fail before the real target passed.
The validator reads source membership, canonical source paths, target dependency, extension embed order, and the retained native test entries.
Plist validation reads both app and extension property lists.
These checks do not prove system rendering.

The scoped macOS package policy change was checked with the advisory Codex doctor command.
It reported one warning and zero failures; the warning concerns local rollout inventory, not plugin behavior.

## Configured host build

The example has an isolated `lib/live_activity_fixture.dart` entrypoint that calls the public platform interface.
The app target references the canonical adapter and attributes, and the embedded Widget Extension references the same attributes and canonical Widget implementation.
The normal example entrypoint remains available.

The native fixture build succeeded on the installed simulator SDK with a command-only `IPHONEOS_DEPLOYMENT_TARGET=16.2` override.
The existing project source remains iOS 13.0; only the new Widget Extension declares an iOS 16.2 minimum.
Flutter's config-only preparation temporarily migrated the project and a Podfile comment to iOS 15.0; only those verified tool-induced changes were restored before the native build.
Generated Flutter configuration was not hand-edited.

Sol review found that the extension's initial marketing version was 1.0 while the app version was 0.1.0.
After correction, an incremental native build succeeded and both built property lists report short version 0.1.0 and build number 1.
Evidence: `/tmp/warm-alarm-platform-fixture-version-build.log` and the app/extension plists in the simulator build product.

## Runtime regression

Actual coordinate input reproduced a sequential lifecycle defect in the preceding simulator binary: Start completed, End completed, then Update ringing incorrectly completed for the same Activity ID.
The sample adapter now selects only active or stale activities; an ended activity can remain in the SDK activity list.
An independent Sol review found no further source-level issue in this guard.
The rebuilt binary returned `notFound` for the same sequential End then Update operation.
A separate active Activity successfully transitioned scheduled → ringing → snoozed → ended, and an unknown ID returned `notFound`.
Evidence: `/tmp/warm-alarm-platform-adapter-build.log` and `/tmp/warm-alarm-live-activity-evidence/08-ended-update-not-found.png`.

Device Hub menu navigation reached the actual simulator Lock Screen and displayed the sample Widget.
The system then requested Live Activity permission; permission changes are awaiting operator approval.
Earlier app-only screenshots did not establish Widget rendering, and accessibility actions sometimes returned before the system view changed.

## Pending acceptance

Simulator lifecycle, Widget rendering, and accessibility evidence are being collected before a visual approval request.
The runtime fixture does not schedule or ring a real alarm.
Issue #19 remains open for final-build physical iPhone Schedule, Stop, and Snooze acceptance.
No physical iPhone was installed or launched during this work.
Operator visual approval, platform merge/publication, cleanup, and durable memory recording remain separate boundaries.
