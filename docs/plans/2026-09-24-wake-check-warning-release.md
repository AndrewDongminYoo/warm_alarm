# Wake-check warning release

## Release order

1. Publish `warm_alarm_platform_interface` 0.1.5 with the optional warning code.
2. Publish `warm_alarm_android` 0.1.4, `warm_alarm_ios` 0.1.11, and `warm_alarm_macos` 0.1.5 with interface `^0.1.5`; the Apple packages add the warning mapping.
3. Publish `warm_alarm` 0.1.6 with the documented behavior and dependency floors for the published interface and platform packages.

Each stage has its own PR, merge, and tag-based publication.
Confirm the new pub.dev version before preparing the next stage because workspace resolution cannot validate published dependency floors.

## Implementation checks

1. Interface model, version, and changelog → verify with `flutter pub get`, interface tests, `flutter analyze warm_alarm_platform_interface`, scoped Dart formatting, and Trunk.
2. Platform mapping, tests, versions, and changelogs → verify with `flutter pub get`, `melos run test`, `flutter analyze`, scoped Dart formatting, Trunk, and platform Pana jobs.
3. App-facing README, version, and dependency floors → verify with `flutter pub get`, `melos run test`, `flutter analyze`, scoped Dart formatting, Trunk, and app-facing Pana.
4. For each merged stage, push a tag matching its package version → verify the GitHub publish workflow and the package version on pub.dev.

## Merge boundary

Prepare each PR and complete its checks and review before requesting operator merge.
Resume publication only after the merge SHA is verified on `main`.
