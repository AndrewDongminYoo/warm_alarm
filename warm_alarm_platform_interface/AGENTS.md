# warm_alarm_platform_interface

The contract package. Owns the abstract `WarmAlarmPlatform` and **all** hand-written public models. Pigeon-generated wire types do not live here.

## STRUCTURE

```plaintext
lib/warm_alarm_platform_interface.dart   # abstract WarmAlarmPlatform + re-exports models
lib/src/method_channel_warm_alarm.dart   # default no-op fallback (returns unsupported/empty)
lib/src/models/
  models.dart                            # barrel export — keep up to date
  warm_alarm_audio.dart
  warm_alarm_capabilities.dart
  warm_alarm_event.dart                  # SEALED hierarchy of alarm lifecycle events
  warm_alarm_notification.dart
  warm_alarm_permission_state.dart
  warm_alarm_readiness.dart
  warm_alarm_schedule.dart
  warm_alarm_schedule_result.dart
  warm_alarm_snapshot.dart
  warm_alarm_support.dart                # WarmAlarmSupportStatus enum
  warm_alarm_volume_fade_step.dart
  warm_alarm_wake_check.dart
test/
```

## WHERE TO LOOK

| Task                                  | Location                                                                                                                                      |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Add a contract method                 | `lib/warm_alarm_platform_interface.dart` (abstract decl) + `lib/src/method_channel_warm_alarm.dart` (no-op default)                           |
| Add/change a public model             | `lib/src/models/<name>.dart` + add to `models.dart` barrel                                                                                    |
| Add a sealed `WarmAlarmEvent` subtype | `lib/src/models/warm_alarm_event.dart` — also extend the matching `WarmAlarmEventTypeWire` enum in **every** platform package's Pigeon schema |

## CONVENTIONS

- `WarmAlarmPlatform` extends `PlatformInterface` and uses the `_token` pattern. Subclasses must `extends` (never `implements`) so future methods can ship with default impls.
- Every new public model goes through `lib/src/models/<name>.dart` and gets exported from `models.dart`. The barrel is in turn re-exported from `lib/warm_alarm_platform_interface.dart`.
- The default `MethodChannelWarmAlarm` returns `unsupported` / empty values, never throws. It's a build-time guard for apps that haven't registered a real platform impl — keep it that way.
- Hand-written models are the **public** boundary. They must be backwards-compatible. If a field is added, give it a default value or make it nullable.

## ANTI-PATTERNS

- Never put Pigeon (`*Wire`) types here. Wire types are private to each platform package's `lib/src/messages.g.dart`.
- Never make `WarmAlarmPlatform` a regular `abstract class` without the `PlatformInterface` token-verify pattern; doing so breaks federated-plugin safety.
- Don't add a contract method without also adding a no-op default in `MethodChannelWarmAlarm` — otherwise apps without a registered platform impl will throw at startup.
- Don't add platform-conditional logic here (no `Platform.isAndroid` etc.). Platform behavior belongs in the platform packages.

## NOTES

- `WarmAlarmEvent` is a sealed class hierarchy. When adding a new subtype, also map it in each platform package's wire-→-public converter and add a `WarmAlarmEventTypeWire` enum value in all three Pigeon schemas. Forgetting one platform = silently dropped events on that platform.
- Models with platform-restricted fields (e.g., `WarmAlarmWakeCheck` is Android-only, `WarmAlarmNotification.androidIcon*` is Android-only) are still defined here; the platform packages decide whether to honor or ignore them.
