# warm_alarm_android

Android implementation. Kotlin-only, package `com.andrew.alarm`. Uses `AlarmManager` + a `mediaPlayback` foreground service. Manifest is auto-merged into the host app.

## STRUCTURE

```plaintext
lib/warm_alarm_android.dart                      # WarmAlarmAndroid extends WarmAlarmPlatform implements WarmAlarmEventsApi
lib/src/messages.g.dart                          # GENERATED Pigeon Dart bindings
pigeons/{messages.dart,copyright.txt}            # Pigeon source of truth
android/
  build.gradle                                   # Java 17, compileSdk 34, minSdk 19, no runtime deps
  src/main/
    AndroidManifest.xml                          # 8 permissions + 2 receivers + 2 services
    kotlin/com/andrew/alarm/
      WarmAlarmPlugin.kt                         # plugin entry; schedule/cancel/permissions/events/kill-warning
      WarmAlarmReceiver.kt                       # ACTION_FIRE, ACTION_WAKE_CHECK_FIRE, ACTION_WAKE_CHECK_DISMISS
      WarmAlarmBootReceiver.kt                   # BOOT_COMPLETED + LOCKED_BOOT_COMPLETED reschedule (directBootAware)
      WarmAlarmForegroundService.kt              # MediaPlayer + notification + full-screen intent
      WarmAlarmStore.kt                          # SharedPreferences-backed schedule/retrigger persistence
      Messages.g.kt                              # GENERATED Pigeon Kotlin bindings
test/
```

## WHERE TO LOOK

| Task                           | Location                                                                                       |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| Permission/manifest changes    | `android/src/main/AndroidManifest.xml` (auto-merged into host)                                 |
| Alarm scheduling logic         | `WarmAlarmPlugin.kt` (shared version-aware `AlarmSchedulingBackend` policy)                    |
| Notification rendering / audio | `WarmAlarmForegroundService.kt` (`mediaPlayback` foreground type)                              |
| Wake-check flow                | `WarmAlarmReceiver.kt` (handles primary fire, wake-check fire, dismiss)                        |
| Boot recovery                  | `WarmAlarmBootReceiver.kt` (`directBootAware="true"`, listens for `LOCKED_BOOT_COMPLETED` too) |
| Persistence                    | `WarmAlarmStore.kt` (SharedPreferences in device-protected storage for direct-boot reads)      |
| Wire-to-public mapping         | `lib/warm_alarm_android.dart`                                                                  |

## CONVENTIONS

- Native Kotlin JVM tests may reuse the existing `org.mockito:mockito-core` dependency for Android platform boundaries while executing the real service logic.
  This is the Android-native exception to the root mocking rule.
  Dart tests must use `mocktail`; do not introduce Dart `mockito`.
- Native package is `com.andrew.alarm` (set in `pubspec.yaml`, `build.gradle`, `Pigeon` options, `AndroidManifest.xml` namespace, and intent action prefix `com.andrew.alarm.ACTION_*`). Keep all five in lockstep when renaming.
- Source root is `android/src/main/kotlin/` (declared in `build.gradle` `sourceSets`). Don't add a `src/main/java/` tree.
- Plugin class registration is via `dartPluginClass: WarmAlarmAndroid` (set in `pubspec.yaml`'s `flutter.plugin.platforms.android` block); the Kotlin `WarmAlarmPlugin` is the channel side. Both must exist.
- The Dart class extends `WarmAlarmPlatform` and implements `WarmAlarmEventsApi` (Pigeon Flutter API). `_ensureEventsApiSetUp()` lazy-binds the events channel — don't bypass it.

## ANTI-PATTERNS

- Don't edit `Messages.g.kt` or `lib/src/messages.g.dart`. Edit `pigeons/messages.dart` and run `melos run generate`.
- Don't add new permissions to the host app's manifest as a workaround — declare them here so the merge propagates.
- On API 23+, use the version-aware scheduling policy so exact alarms can fire during idle; do not replace its idle-capable calls with `setExact()`.
  Preserve `setExact()` for the API 19–22 legacy branch, where `setExactAndAllowWhileIdle()` is unavailable.
- Don't drop the `directBootAware="true"` flag on `WarmAlarmBootReceiver` — alarms scheduled before unlock won't restore otherwise.
- Don't switch the foreground service type away from `mediaPlayback` without auditing Android 14+ permission requirements (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`).
- Don't add Java sources; this is a Kotlin-only module.

## NOTES

- The intent action namespace `com.andrew.alarm.ACTION_FIRE` / `ACTION_WAKE_CHECK_FIRE` / `ACTION_WAKE_CHECK_DISMISS` is hard-coded in both `AndroidManifest.xml` and the Kotlin source. Renaming requires both sides.
- The example app pins `warm_alarm_android` directly in its `pubspec.yaml` (in addition to the federated `warm_alarm` dependency). That's intentional for E2E pinning — don't mirror that in real consumer apps.
