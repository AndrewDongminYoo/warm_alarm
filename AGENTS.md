# Repository Guidelines

## Project Structure & Module Organization

This repository is a Dart workspace managed with `melos` for a federated Flutter plugin. Core packages live at the root:

- `warm_alarm/`: public plugin package plus the runnable example app in `warm_alarm/example/`
- `warm_alarm_platform_interface/`: shared API contract for all platforms
- `warm_alarm_android/`, `warm_alarm_ios/`, `warm_alarm_macos/`: platform implementations

Within each package, keep public exports in `lib/`, internal helpers in `lib/src/`, tests in `test/`, and Pigeon inputs in `pigeons/` when platform channels are involved.

## Build, Test, and Development Commands

- `flutter pub get`: resolve the workspace from the repo root
- `melos run generate`: regenerate Pigeon outputs after editing any `pigeons/messages.dart`
- `melos run format`: apply Dart fixes and format all packages to the repo standard
- `melos run test`: run unit tests across packages
- `melos run test:ci`: run tests with coverage output for CI-style verification
- `trunk check`: run repo-wide non-Dart checks such as spelling, Markdown, YAML, and Kotlin linting
- `cd warm_alarm/example && fluttium test flows/test_platform_name.yaml -d macos`: run the example end-to-end flow; swap `macos` for `android` or `iPhone` as needed

## Coding Style & Naming Conventions

Use Dart 3.11+ conventions with `very_good_analysis`: 2-space indentation, `snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. The repo formats Dart at 120 columns. Do not hand-edit generated files such as `lib/src/messages.g.dart`, `Messages.g.kt`, or `Messages.g.swift`; update the Pigeon source and regenerate instead.

## Testing Guidelines

Unit tests use `flutter_test`; mocks use `mocktail`. Place tests in the package you changed and name them `*_test.dart`. For platform-channel changes, update tests in both the package and the example flow when behavior changes across Android, iOS, or macOS.

## Commit & Pull Request Guidelines

Recent history follows Conventional Commits such as `feat: ...`, `chore: ...`, and `ci: ...`; keep commit messages and PR titles in that format because semantic PR validation runs in CI. Use `.github/PULL_REQUEST_TEMPLATE.md`: add a short description and mark the correct change type. Call out affected platforms and include screenshots only when the example app UI changes.
