# Platform release after interface 0.1.4

## Contract

Publish platform implementations only after the interface contract is available on pub.dev.
PR #57 merged as `b61b5c405a25db8c289fec233d8a417506a0220e`, and the `warm_alarm_platform_interface-v0.1.4` tag published interface 0.1.4 successfully.
Prepare Android 0.1.3, iOS 0.1.10, and macOS 0.1.3 with interface `^0.1.4`.
Keep facade validation, forwarding, and dependency changes for the following release stage.

Reuse the reviewed native implementations from PR #56 at `9bcddb51267aca7074312e372602cfb59244e4ab`.
Preserve generated Pigeon boundaries and the Android permission callback lifecycle.
Complete the missing configured-host Live Activity fixture by referencing the canonical app and Widget sample sources from the existing Flutter example.
The fixture uses the public platform interface because facade forwarding is a later release stage.

## Success criteria

1. Extract platform sources and raise release constraints → verify source parity, `flutter pub get`, and generated output parity after `melos run generate`.
2. Preserve Dart mapping and compatible defaults → verify workspace Flutter tests, `flutter analyze --no-pub`, and scoped Dart formatting.
3. Exercise native persistence and playback policies → verify Android unit tests, iOS RunnerTests, and macOS SwiftPM tests with the real Flutter framework; run heavy jobs sequentially.
4. Make macOS native coverage continuous → verify the exact new CI command and hosted execution of its 18 native tests.
5. Exercise the shipped ActivityKit sample → build the configured app and Widget targets, then verify start, visible updates, end, unknown identifiers, and authorization behavior on an iOS simulator.
6. Prepare the platform PR → verify independent local review, current-head hosted CI including Pana against published dependencies, and hosted review findings.

## Remaining acceptance

Issue #19 remains open until a supported physical iPhone exercises final-build Schedule, Stop, and Snooze.
Simulator results cannot establish that acceptance, and the daily iPhone has not been authorized for installation or launch.
Issue #21 requires actual configured-host ActivityKit lifecycle and rendered Widget evidence.
The PR remains draft while operator visual approval is pending.
No issue is closed by the release extraction alone.

## Authority and precedent

The operator resumed the approved PR loop after merging #57, following the explicit request to merge and publish interface 0.1.4.
That continuation covers the interface publication and preparation of the next platform PR.
Future platform merges and publications retain their explicit approval boundary.
Cleanup and durable memory recording were not requested.

The federated release-order precedent requires interface publication before platform dependency floors and platform publication before the facade stage.
Source: `/Users/dongminyu/.claude/projects/-Users-dongminyu-Development-01-personal-warm-alarm/memory/federated-release-order.md`.
The Android permission callback precedent confirms that Activity configuration changes must preserve pending callbacks.
Source: `wiki/sources/claude--projects---users-dongminyu-development-01-personal-warm-alarm--memory--android-permission-callback-lifecycle.md`.
