# Apple foreground default alarm sound

## Problem

[Issue #70](https://github.com/AndrewDongminYoo/warm_alarm/issues/70) identifies a silent foreground path on iOS User Notifications and macOS.
The default audio configuration has no file or asset, so the delegate creates no audio player, but its presentation callback also omits notification sound.

## Scope

Request notification sound when an accepted foreground alarm has no custom file or asset source.
Retain player-only sound for custom sources to avoid duplicate playback.
Preserve iOS occurrence validation and duplicate suppression.
Use the sound already attached to the notification content.

## Non-goals

Do not change AlarmKit, background scheduling, public Dart APIs, generated Pigeon files, or package versions.
Do not expand playback recovery for invalid custom audio files or implement the other audit issues.

## Acceptance criteria

1. Native delegate callback tests request `.sound` for the default and empty-source configurations on both platforms.
2. A custom audio source suppresses notification sound while preserving the existing player path.
3. Cancelled, replaced, and duplicate iOS occurrences remain suppressed.
4. Native suites, Flutter analysis and tests, and scoped formatting and lint checks pass.
5. Foreground execution on both platforms confirms audible default delivery; callback options alone do not establish physical audibility.

## Constraints and precedent

Run heavy native builds sequentially on the local Mac.
Use a simulator for iOS; the operator's daily phone is outside this task's device scope.
There are no visual design changes requiring visual approval.
The Oracle source `wiki/sources/warm_alarm--readme.md` establishes platform-honest behavior and private Pigeon boundaries; the fix restores the existing native notification path without extending public capability claims.
