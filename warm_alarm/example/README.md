# warm_alarm_example

Demonstrates how to use the warm_alarm plugin.

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

| Result                                     | Warning code           | Message                                                     |
| ------------------------------------------ | ---------------------- | ----------------------------------------------------------- |
| Android with exact-alarm permission        | `none`                 | `none`                                                      |
| iOS with wake-check requested              | `unsupportedWakeCheck` | Wake-check is not supported on iOS, plus any native warning |
| A native warning without a structured code | `unclassified`         | The original native warning                                 |

The screen replaces the previous warning after each successful request, including a result with no warning.
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
Inspect the full warning message for additional fallback details; a wake-check warning alone does not identify the scheduling backend.
Verify the system alarm controls separately because User Notifications fallback does not verify AlarmKit behavior.
The separate custom Live Activity fixture remains available through `lib/live_activity_fixture.dart`.
