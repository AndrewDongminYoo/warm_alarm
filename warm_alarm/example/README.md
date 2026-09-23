# warm_alarm_example

Demonstrates how to use the warm_alarm plugin.

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
The UI displays `Schedule warning` when the plugin falls back to User Notifications; a fallback does not verify AlarmKit behavior.
The separate custom Live Activity fixture remains available through `lib/live_activity_fixture.dart`.
