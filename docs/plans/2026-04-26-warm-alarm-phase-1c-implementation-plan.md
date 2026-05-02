# Warm Alarm Phase 1C: Apple Alarm Proof Implementation Plan

> **Status:** COMPLETE (implemented 2026-04-26)

**Goal:** Replace iOS and macOS Phase 1A stubs with real `UNUserNotificationCenter` scheduling,
`AVAudioPlayer` audio playback, stop/snooze notification actions, and `WarmAlarmEventsApi`
event emission to Dart.

**Architecture:** Both platforms share the same three-layer structure:

- `WarmAlarmStore` — UserDefaults + Codable persistence
- `WarmAlarmDelegate` — UNUserNotificationCenterDelegate, owns audio and event emission
- `WarmAlarmPlugin` — Pigeon API surface (real permission/readiness/scheduling)

iOS additionally configures `AVAudioSession.Category.playback` for alarm-priority audio;
macOS uses `AVAudioPlayer` directly without a session category (`AVAudioSession` unavailable).

**Tech Stack:** Swift, `UserNotifications`, `AVFoundation`, `UserDefaults` + `Codable`,
Pigeon `FlutterApi` (`WarmAlarmEventsApi`), `mocktail` (Dart tests)

---

## Scope Decisions

- **Audio:** `AVAudioSession.Category.playback` (iOS) + `AVAudioPlayer` for full alarm audio
- **macOS:** same depth as iOS
- **Live Activity (`ActivityKit`):** excluded — Phase 3+

---

## Tasks Completed

| Task | Description                                                                                    |
| ---- | ---------------------------------------------------------------------------------------------- |
| D1   | Wire `WarmAlarmEventsApi` in `warm_alarm_ios/lib/warm_alarm_ios.dart` (deferred setUp pattern) |
| D2   | Wire `WarmAlarmEventsApi` in `warm_alarm_macos/lib/warm_alarm_macos.dart`                      |
| I1   | Create `WarmAlarmStore.swift` for iOS (UserDefaults + Codable)                                 |
| I2   | Create `WarmAlarmDelegate.swift` for iOS (UNUserNotificationCenterDelegate + AVAudioPlayer)    |
| I3   | Replace stub `WarmAlarmPlugin.swift` for iOS with real UNUserNotificationCenter implementation |
| I4   | iOS end-to-end verification (build + format + tests)                                           |
| M1   | Create `WarmAlarmStore.swift` for macOS (identical to iOS)                                     |
| M2   | Create `WarmAlarmDelegate.swift` for macOS (no AVAudioSession)                                 |
| M3   | Replace stub `WarmAlarmPlugin.swift` for macOS with real implementation                        |
| M4   | macOS end-to-end verification                                                                  |

---

## Final Commits

| Hash    | Description                                                                             |
| ------- | --------------------------------------------------------------------------------------- |
| ea53ea5 | feat(macos): add WarmAlarmStore, WarmAlarmDelegate, and real plugin implementation      |
| 7a25392 | feat(ios): implement real UNUserNotificationCenter scheduling and permission inspection |
| 6206d41 | fix(ios): simplify WarmAlarmDelegate import to use Flutter unconditionally              |
| aa6c7c3 | feat(ios): add WarmAlarmDelegate for notification delivery, audio, and event emission   |
| 60d4591 | feat(ios): add WarmAlarmStore for UserDefaults-backed schedule persistence              |
| cde45fb | feat(macos): wire WarmAlarmEventsApi event channel to Dart stream                       |
| ec0e3ac | fix(ios): defer WarmAlarmEventsApi.setUp to first events access                         |
| c551d34 | feat(ios): wire WarmAlarmEventsApi event channel to Dart stream                         |

---

## Definition of Done (verified)

✓ WarmAlarmEventsApi wired in Dart for iOS and macOS (deferred setUp pattern)
✓ iOS: WarmAlarmStore.swift (UserDefaults + Codable)
✓ iOS: WarmAlarmDelegate.swift (UNUserNotificationCenterDelegate + AVAudioPlayer + AVAudioSession)
✓ iOS: Real getCapabilities / getPermissionState / getReadiness / scheduleAlarm / cancelAlarm
✓ iOS: WarmAlarmScheduled emitted on successful schedule
✓ iOS: WarmAlarmFired emitted in willPresent / didReceive default action
✓ iOS: WarmAlarmStopped / WarmAlarmSnoozed emitted on notification actions
✓ iOS: WarmAlarmFailed emitted if UNUserNotificationCenter.add fails
✓ macOS: same structure
✓ melos run test passes (all 5 packages — 14 Dart tests)
✓ flutter build ios --simulator --no-codesign passes
✓ flutter build macos --debug passes

## Not in Phase 1C Scope (deferred)

- Live Activity / Dynamic Island (`ActivityKit`) — Phase 3+
- iOS background audio without foreground (requires host app `audio` background mode + Silent Push)
- Reboot persistence on iOS/macOS
- Request-permission flow from Dart (host app calls `requestAuthorization`)
- Wake-check — Phase 2
