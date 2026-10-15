# Android player initialization cleanup

## Problem

`createPlayer` allocates a `MediaPlayer` before configuring, preparing, and starting it.
If any initialization step throws, the service has not yet assigned its `mediaPlayer` field, so the outer failure handler cannot release that local instance.
This is the separate finding reported during PR #81 and subsequently approved for correction.

## Contract and scope

After allocation, an initialization exception must trigger a release attempt before the original exception reaches the existing playback failure handler.
A release exception must not replace the original failure message.
Successful initialization must still return the player to service ownership without releasing it.
File, asset, and default-alarm sources continue to use this shared helper.
Preserve the existing failure event, vibration cleanup, and service shutdown behavior.

Do not change source selection, overlap policy, public APIs, dependencies, permissions, Pigeon output, or Apple behavior.
There is no visual output requiring operator approval.

## Acceptance and limits

1. Service-command regressions inject failures in data-source configuration, preparation, and playback start and verify a release attempt without an invalid-state stop call.
2. A regression injects both initialization and release failures and reads the persisted `AUDIO_PLAYBACK_FAILED` event to verify the original message.
3. The new tests fail for missing release on the unchanged implementation and pass after the fix.
4. Existing successful playback and overlap regressions remain green, along with the native unit suite, Android Dart tests, Flutter analysis, scoped formatting, and Trunk checks.

The JVM harness executes real service and event-persistence code with mocked Android boundaries.
It verifies cleanup attempts, callback state, and error propagation, not physical sound output or successful operating-system resource release when `release()` itself throws.
Asset-descriptor and default-ringtone platform behavior are not directly exercised by these service tests.
The existing project Oracle lookup for playback lifecycle and MediaPlayer returned `[no precedent found]`; source behavior and the approved finding define this correction.
