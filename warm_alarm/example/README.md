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
This example still uses the User Notifications fallback on iOS; adding a sound does not enable AlarmKit or continuous ringing while locked.
Schedule a new alarm after installing the sound-enabled build; an already pending notification may still reference the default sound.
