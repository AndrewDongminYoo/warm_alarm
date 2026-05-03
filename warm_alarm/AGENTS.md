# warm_alarm

App-facing facade. Thin wrapper that forwards every call to `WarmAlarmPlatform.instance`. **No platform code, no models, no Pigeon here** — those live in the interface and platform packages.

## STRUCTURE

```plaintext
lib/warm_alarm.dart      # SOLE source file: the `WarmAlarm` static facade
test/warm_alarm_test.dart
example/                 # see example/AGENTS.md
```

There is intentionally no `lib/src/` in this package. If you reach for one, you're probably putting code in the wrong package.

## WHERE TO LOOK

| Task                               | Location                                                                                                                             |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Add a static method on `WarmAlarm` | `lib/warm_alarm.dart` (forward to `_platform.<method>` after adding it to the platform interface)                                    |
| Add a Dart-only convenience helper | `lib/warm_alarm.dart` — see `hasAlarm()` / `getAlarm()` for the pattern (compose existing platform calls; do not bypass `_platform`) |
| Reference a model                  | Already re-exported here via `export 'package:warm_alarm_platform_interface/...'` in `lib/warm_alarm.dart`                           |

## CONVENTIONS

- Every public method is `static` and forwards to `WarmAlarmPlatform.instance` through the private `_platform` getter. Don't break that pattern — it's what lets tests swap in fakes via `WarmAlarmPlatform.instance = ...`.
- This package re-exports the entire platform interface (`export 'package:warm_alarm_platform_interface/...';`). Consumers should `import 'package:warm_alarm/warm_alarm.dart';` and never need to import the interface directly.
- `pubspec.yaml` declares `flutter.plugin.platforms.{android,ios,macos}.default_package` for federation. Keep those three lines in sync with new platform packages.

## ANTI-PATTERNS

- Don't add models, enums, or Pigeon files here — those belong in `warm_alarm_platform_interface/`.
- Don't import any `warm_alarm_<platform>` package directly. Reach the platform via `WarmAlarmPlatform.instance` only.
- Don't add `lib/src/` or any private files; this package stays single-file by design.
- Don't introduce platform-channel calls. Use the platform interface; platform packages handle channels.

## NOTES

`WarmAlarm.hasAlarm()` and `WarmAlarm.getAlarm(id)` filter `getScheduledAlarms()` by `scheduledAt.isAfter(now)` in Dart. If you need different semantics (e.g., include past-but-ringing alarms), add a new method on the platform interface rather than changing the filter here.
