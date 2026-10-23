# warm_alarm_example

Demonstrates how to use the warm_alarm plugin.

## Voice alarm demo

The macOS host starts with a 1280×720 content area for a 16:9 presentation.
At widths of at least 1100 and heights of at least 640 logical pixels with text scaling at most 1.3, the screen uses three dashboard columns: voice and events, alarm controls and results, permissions and capabilities.
The dashboard has no whole-page scroll; long results and events scroll within their own areas.
At narrower widths, recording and scheduling stay side by side from 620 logical pixels, or stack below that width and with larger text.
In that scrolling layout, permission controls and capability values are behind **Show platform details**; **Inspect Alarm API** opens them automatically.
Fully quit and relaunch the macOS host to apply its new initial window size; hot reload does not recreate the native window.

1. Press **Record my voice** and respond to the operating system's microphone prompt yourself.
2. Say a short wake-up message, then press **Save recording**.
   Recording stops automatically after about 15 seconds while the app remains active; backgrounding the app also attempts to stop and save it.
3. Press **Preview voice** to check the saved audio.
4. Select **My voice**, choose 15 seconds or 1 minute, and schedule the alarm.
   The file path is passed to `warm_alarm`; `prepareSystemSound` prepares the Apple system-sound copy when the backend supports it.
5. Observe the actual alarm and event log, then press **Cancel alarm** to remove the demo alarm (ID 42), including any pending follow-up.
   Preview and recording are disabled while this screen owns an active alarm to avoid competing audio sessions.

**Demo chime** remains available if microphone permission is denied.
A scheduled request is not proof that audio played or that AlarmKit was selected.
Check foreground and background behavior on each target separately; simulators do not establish physical-device audio behavior.

`record`, `audioplayers`, and `path_provider` are example-only dependencies for capture, preview, and app-private storage.
Microphone access is declared in Android's manifest, iOS/macOS usage descriptions, and both macOS audio-input entitlements.
These declarations do not grant OS permission.
Rebuild the native host after resolving dependencies; hot reload cannot add native plugins or entitlements.

Recordings are mono WAV files at a requested 22,050 Hz in the app support directory's `voice_recordings` folder.
`latest.json` restores the latest saved recording on launch.
Older files are retained because an already scheduled alarm can still reference them.
This example has no upload feature or recording library cleanup UI.
For cleanup, cancel demo alarms first, stop the app, and remove only its `voice_recordings` folder from the app's own support container.
Do not delete recordings while an alarm still references them.

Permission and audio errors show a short recovery message and scroll it into view.
Full exception details remain in debug logs.
If saving fails and recorder shutdown cannot be confirmed, **Save recording** stays available and scheduling stays disabled; retry stopping or close the app before continuing.
A failed notification permission request still requires an OS settings check; this screen does not override denied permission.

### Local checks

From `warm_alarm/example`:

```bash
flutter pub get
dart format lib/main.dart lib/voice_audio.dart test/inspection_test.dart test/voice_audio_test.dart
flutter analyze --no-pub
flutter test --no-pub --concurrency 1
flutter run --no-pub -d macos
```

Widget tests inject fake audio and platform implementations: they verify UI recovery and schedule arguments without requesting a microphone or scheduling native alarms.
They do not verify native capture, audible playback, permissions, or eventual delivery.

## Inspection and presentation demos

Press **Inspect Alarm API** to display readiness, reason codes, and all six capability values.
The app refreshes readiness and capabilities after returning from settings.
An empty reason list is shown as `none`.

### Demo A: notification permission on Android

1. Record the device model, Android version, package versions, and build commit used for the recording.
2. Grant exact-alarm and full-screen permissions where required, then disable only the app's notification permission in system settings.
3. Return to the app and press **Inspect Alarm API**.
   Expect `Readiness: limited` and `Readiness reasons: notificationPermissionDenied`.
4. Press **Open readiness settings**, enable notifications, and return to the app.
   Expect `Readiness: ready` and `Readiness reasons: none` if the other permissions remain granted.

The result returned when settings opens describes the state before the user changes it.
The app reads the outcome again on resume.
Do not use `blocked → ready` as the expected transition: Android reports missing permissions as `limited`, while Apple's User Notifications backend remains `limited` after notification permission is granted.
An authorized AlarmKit backend can be ready without notification permission.

### Demo B: the same wake-check request on Android and iOS

Use **Schedule 1 minute alarm** on both platforms.
The existing request includes wake-check.
On Android, grant exact-alarm permission before recording so the result is not affected by an inexact-scheduling warning.
On iOS, record the OS version and AlarmKit authorization state because the selected backend can differ.

| Result                                     | Warning code           | Message                            |
| ------------------------------------------ | ---------------------- | ---------------------------------- |
| Android with exact-alarm permission        | `none`                 | `none`                             |
| iOS with wake-check requested              | `unsupportedWakeCheck` | Wake-check is not supported on iOS |
| A native warning without a structured code | `unclassified`         | The original native warning        |

The screen replaces the previous warning after each successful request, including a result with no warning.
The screen iterates `result.warnings` and displays every diagnostic, preserving each code and full message.
Wake-check is enabled by default and can be disabled explicitly in the alarm panel.
These demos show inspection and scheduling results; they do not establish that a future alarm will fire.
Before recording, verify the expected values on the chosen devices and keep those device conditions with the video.

## Test sound

The example uses an original eight-second synthesized chime in `assets/audio/alarm_ring.wav`.
Foreground app playback plays it once (`loop: false`).
The iOS Runner also bundles `alarm_ring.caf` for notifications received while the app is backgrounded or the phone is locked.
Both files contain the same mono, 22,050 Hz, 16-bit PCM audio.

After replacing the WAV source, regenerate the notification resource from this directory on macOS:

```bash
afconvert -f caff -d LEI16 assets/audio/alarm_ring.wav ios/Runner/alarm_ring.caf
```

Keep the notification sound below 30 seconds, as required by [Apple's notification sound documentation](https://developer.apple.com/documentation/usernotifications/unnotificationsound).
Schedule a new alarm after installing the sound-enabled build; an already pending notification may still reference the default sound.

## AlarmKit device check

The iOS host includes `NSAlarmKitUsageDescription` and an AlarmKit countdown presentation in its Widget Extension.
The one-minute alarm button schedules a five-minute Snooze so the native Schedule, Stop, and Snooze flow can be checked on an iOS 26 or later device.
If AlarmKit asks for authorization, allow it, then check that the alarm appears with system alarm controls rather than a notification banner.
The request also includes wake-check, so `unsupportedWakeCheck` is expected on iOS even when AlarmKit succeeds.
Inspect every warning shown by the example for additional fallback details.
A wake-check warning alone does not identify the scheduling backend or exclude a simultaneous native fallback warning.
Verify the system alarm controls separately because User Notifications fallback does not verify AlarmKit behavior.
The separate custom Live Activity fixture remains available through `lib/live_activity_fixture.dart`.
