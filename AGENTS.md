# PROJECT KNOWLEDGE BASE

**Generated:** 2026-05-03T07:04Z
**Commit:** e8d3c3c
**Branch:** main

## OVERVIEW

Federated Flutter plugin for platform-honest alarms (Android / iOS / macOS) in a Melos-managed Dart workspace. All native ↔ Dart wiring is Pigeon-generated.

## STRUCTURE

```plaintext
warm_alarm/                          # app-facing facade + example app
warm_alarm_platform_interface/       # abstract contract + ALL hand-written public models
warm_alarm_android/                  # Kotlin impl (AlarmManager + ForegroundService)
warm_alarm_ios/                      # Swift impl (UNUserNotificationCenter + AVAudioSession)
warm_alarm_macos/                    # Swift impl (no AVAudioSession; AppKit lifecycle)
docs/{plans,specs,notes}/            # phase plans, design specs, working notes
.github/workflows/                   # one CI workflow per package + ci.yaml + license_check.yaml
.trunk/, .cspell/                    # non-Dart linters + spell dictionaries
pubspec.yaml                         # Melos config lives HERE (no melos.yaml)
```

## WHERE TO LOOK

| Task                              | Location                                                                                                  |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Add/change a public API method    | `warm_alarm_platform_interface/lib/warm_alarm_platform_interface.dart` + `warm_alarm/lib/warm_alarm.dart` |
| Add/change a public model         | `warm_alarm_platform_interface/lib/src/models/*.dart` (then re-export from `models.dart`)                 |
| Change the wire protocol (Pigeon) | `<platform_pkg>/pigeons/messages.dart` → `melos run generate`                                             |
| Android native behavior           | `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/` + `AndroidManifest.xml`                    |
| iOS native behavior               | `warm_alarm_ios/ios/warm_alarm_ios/Sources/warm_alarm_ios/`                                               |
| macOS native behavior             | `warm_alarm_macos/macos/warm_alarm_macos/Sources/warm_alarm_macos/`                                       |
| End-to-end UI smoke test          | `warm_alarm/example/flows/test_readiness.yaml` (Fluttium)                                                 |
| Custom Fluttium actions           | `warm_alarm/example/actions/check_readiness/` (separate package)                                          |

## CONVENTIONS

- **Format width: 120 columns** (not Dart's default 80). Configured via `format_line_length: 120` in every per-package CI workflow and `melos run format`.
- Lints: `very_good_analysis` everywhere, with these errors set to `ignore` in each `analysis_options.yaml`: `lines_longer_than_80_chars`, `one_member_abstracts`, `public_member_api_docs`. The three platform packages additionally exclude `**/*.g.dart` from analysis.
- `melos.yaml` does **not** exist; Melos config lives under the `melos:` key in root `pubspec.yaml`.
- `pubspec.lock` is `.gitignore`d (do not commit).
- Trunk runs `cspell`, `actionlint`, `checkov`, `git-diff-check`, `ktlint`, `markdownlint`, `oxipng`, `prettier`, `svgo`, `trufflehog`, `yamllint`. Trunk's `dart` linter is **disabled** (Dart goes through `melos run format` / `format:ci` instead).
- Pre-commit/pre-push hooks come from Trunk (`trunk-fmt-pre-commit`, `trunk-check-pre-push`); there is no `.husky` / `lefthook` / `.pre-commit-config.yaml`.
- PR titles must be Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`, …); enforced by `.github/workflows/ci.yaml` (semantic_pull_request).
- Mocks: `mocktail` only. Do **not** introduce `mockito`.
- Spell-check uses VGV's allow/forbid dictionaries plus `.cspell/custom-dictionary.txt`. Add new project terms there, not inline `cspell:disable`.
- Apple packages declare `swift_version = '6.1'`; Android targets `compileSdk 34`, `minSdk 19`, Java 17.

## ANTI-PATTERNS (THIS PROJECT)

- **Never hand-edit Pigeon outputs** (6 files):
  `<platform_pkg>/lib/src/messages.g.dart`,
  `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/Messages.g.kt`,
  `warm_alarm_<ios|macos>/<platform>/warm_alarm_<ios|macos>/Sources/warm_alarm_<ios|macos>/Messages.g.swift`.
  Edit `pigeons/messages.dart` and run `melos run generate`.
- Never re-export Pigeon DTOs (the `*Wire` types) from any package. Public models are hand-written in `warm_alarm_platform_interface/lib/src/models/`; wire types stay in each platform package's private `lib/src/`.
- Never `implements WarmAlarmPlatform`. Always `extends`. New methods get default impls so `extends`-based subclasses stay forward-compatible.
- Never add `warm_alarm_android`, `warm_alarm_ios`, or `warm_alarm_macos` directly to an app's `pubspec.yaml`. They are endorsed; depending on `warm_alarm` pulls them in transparently. (The example app is the one exception: it pins `warm_alarm_android` for E2E control.)
- Never edit auto-generated Flutter scaffolding under `warm_alarm/example/{ios,macos,android}/Flutter/` (`Generated.xcconfig`, `flutter_export_environment.sh`, `GeneratedPluginRegistrant.*`, ephemeral podspecs). They are regenerated by the Flutter tool.
- Don't widen analyzer overrides per-file with `// ignore_for_file:` — fix the code or update the package's `analysis_options.yaml` deliberately.
- Don't expand the Android manifest's permission set without also updating `getCapabilities()`/`getReadiness()` and the README permissions table.

## COMMANDS

```bash
flutter pub get                                # resolve workspace
melos run get                                  # equivalent: very_good packages get --recursive --ignore=.trunk
melos run generate                             # regenerate Pigeon for packages depending on `pigeon`
melos run test                                 # flutter test --coverage --test-randomize-ordering-seed random (per package)
melos run test:ci                              # same, --concurrency 4
melos run format                               # dart fix --apply ; dart format .
melos run format:ci                            # check-only (--set-exit-if-changed)
trunk check                                    # cspell / markdownlint / ktlint / yamllint / actionlint / etc.

# E2E (per platform)
cd warm_alarm/example && fluttium test flows/test_readiness.yaml -d android
cd warm_alarm/example && fluttium test flows/test_readiness.yaml -d iPhone
cd warm_alarm/example && fluttium test flows/test_readiness.yaml -d macos
```

## NOTES

- Each platform package has its **own** Pigeon schema (`<pkg>/pigeons/messages.dart`). They can diverge intentionally — keep semantically-shared enum/class names aligned across the three to avoid model-mapping drift.
- `warm_alarm_macos` ships a separate copy of the iOS Swift implementation (not a symlink). Behavioral changes meant for both Apple platforms must be applied twice.
- The example app under `warm_alarm/example/` is part of the Dart workspace. The nested Fluttium action package at `warm_alarm/example/actions/check_readiness/` is **excluded** from Melos scripts but included in the workspace by root `pubspec.yaml`.
- See per-package `AGENTS.md` (`warm_alarm/`, `warm_alarm_platform_interface/`, `warm_alarm_<android|ios|macos>/`, `warm_alarm/example/`) for package-local rules.
