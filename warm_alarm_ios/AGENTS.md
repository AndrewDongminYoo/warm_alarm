# warm_alarm_ios

iOS implementation. Swift 6.1, iOS 13+. Uses `UNUserNotificationCenter` + `AVAudioPlayer` + `AVAudioSession(.playback)`.

## STRUCTURE

```plaintext
lib/warm_alarm_ios.dart                                  # WarmAlarmIOS extends WarmAlarmPlatform implements WarmAlarmEventsApi
lib/src/messages.g.dart                                  # GENERATED Pigeon Dart bindings
pigeons/{messages.dart,copyright.txt}                    # Pigeon source of truth
ios/
  warm_alarm_ios.podspec                                 # CocoaPods: Flutter dep, iOS 13.0, Swift 6.1
  warm_alarm_ios/
    Package.swift                                        # SwiftPM manifest (PrivacyInfo.xcprivacy is a TODO placeholder)
    Sources/warm_alarm_ios/
      WarmAlarmPlugin.swift                              # plugin entry; lifecycle observers; startup reschedule
      WarmAlarmDelegate.swift                            # UNUserNotificationCenter delegate; Stop/Snooze; AVAudioPlayer; fade; recurrence reschedule
      WarmAlarmStore.swift                               # UserDefaults-backed Codable schedule store
      Messages.g.swift                                   # GENERATED Pigeon Swift bindings
    Tests/warm_alarm_ios_tests/
test/
```

## WHERE TO LOOK

| Task                                          | Location                                                                         |
| --------------------------------------------- | -------------------------------------------------------------------------------- |
| Notification scheduling / categories          | `WarmAlarmPlugin.swift` + `WarmAlarmDelegate.swift`                              |
| Audio playback / fade-in / Silent-mode bypass | `WarmAlarmDelegate.swift` (`AVAudioSession`, `AVAudioPlayer`, timer-driven fade) |
| Persistence                                   | `WarmAlarmStore.swift`                                                           |
| Wire-to-public mapping                        | `lib/warm_alarm_ios.dart`                                                        |
| Pigeon channel registration                   | `WarmAlarmPlugin.swift` (calls `WarmAlarmApi.setUp(...)`)                        |

## CONVENTIONS

- Both CocoaPods (`warm_alarm_ios.podspec`) and SwiftPM (`Package.swift`) ship in this package. Source files for both come from the single `Sources/warm_alarm_ios/` tree; don't duplicate.
- `swift_version = '6.1'` in the podspec. Code may rely on Swift 6 concurrency; do not lower the version without auditing `@Sendable` usages.
- Plugin-level `Info.plist` keys / background modes / entitlements are **not** declared in this package — they're the consuming app's responsibility (notification permission prompt at runtime is enough for the foreground case).

## ANTI-PATTERNS

- Don't edit `Messages.g.swift` or `lib/src/messages.g.dart`. Edit `pigeons/messages.dart` and run `melos run generate`.
- Don't introduce app-side `Info.plist`/entitlements changes from inside the plugin — document them in the README instead and let consumers add them.
- Don't change `AVAudioSession` category to anything other than `.playback`; `.ambient` and friends will be silenced by the device's mute switch.
- Don't drop the recurrence reschedule logic in `WarmAlarmDelegate`; iOS does not support arbitrary weekday-masked recurring `UNNotificationRequest` triggers natively.

## NOTES

- iOS does **not** emit wake-check events (`WarmAlarmWakeCheckShown` / `Dismissed` / `Expired` / `WarmAlarmRetriggered`). Keep `getCapabilities().wakeCheck = unsupported`.
- The `Package.swift` privacy-manifest comment is a TODO; if you ship a `PrivacyInfo.xcprivacy`, also wire it into `s.resource_bundles` in the podspec.
- Behavioral changes intended for both Apple platforms must be applied to `warm_alarm_macos` separately — it's a copy, not a symlink. Diff the two implementations after any non-trivial change.
