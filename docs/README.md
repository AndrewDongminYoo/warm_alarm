# Documentation

Start with the [project README](../README.md) for installation and the public API overview.
Use the package guides for current configuration and behavior.

## Package guides

| Guide                                                            | Scope                                                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [Public facade](../warm_alarm/README.md)                         | Audio precedence, lifecycle events, warnings, and public API usage                 |
| [Example app](../warm_alarm/example/README.md)                   | Voice alarm walkthrough, local checks, CI coverage, and manual device verification |
| [Android](../warm_alarm_android/README.md)                       | Android permissions, scheduling, playback, and native checks                       |
| [iOS](../warm_alarm_ios/README.md)                               | AlarmKit, notification fallback, host configuration, and platform limits           |
| [macOS](../warm_alarm_macos/README.md)                           | macOS notification and audio behavior                                              |
| [Platform interface](../warm_alarm_platform_interface/README.md) | Shared models and platform contracts                                               |

## Tooling and decisions

- [Pana workspace context](notes/2026-08-13-pana-workspace-context.md) records why package analysis uses `--project-root .`.
  The current command lives in [the reusable Pana workflow](../.github/workflows/pana.yaml); the note's versions and scores are historical evidence.
- [Dart SDK policy](specs/2026-10-09-project-dart-sdk.md) explains the package SDK contract.
- [Example host AGP migration deferral](notes/2026-10-17-example-host-agp-10-deferral.md) records the migration trigger and its required checks.
- [Scheduling warning contract](specs/2026-10-17-scheduling-warnings-list.md) describes the warning list and compatibility getter.

## Design and history

- `specs/` contains design contracts and their platform constraints.
- `plans/` contains implementation plans and release sequences.
- `notes/` contains dated decisions, investigations, and verification evidence.

Check a document's date and pinned revision before treating historical commands, versions, or results as current behavior.
Use the package guides and workflows for executable instructions.
Presentation recordings, rehearsal scripts, and temporary verification receipts are kept outside the repository.
