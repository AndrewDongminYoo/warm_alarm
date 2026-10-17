# Alarm delivery and action safety

## Problem

A custom Apple audio source can fail while the foreground notification suppresses system sound.
Accepted Stop/Snooze actions can stop another alarm's player, and macOS actions from a replaced schedule can mutate the replacement.
macOS Snooze currently reports success before notification registration completes.
The notification category, action-title, and Android retained-notification implementations also diverge from their public options.

## Required behavior

- A missing or undecodable custom source, or rejected player start, reports an audio failure and requests notification sound when foreground presentation is available.
  Only successful custom playback suppresses duplicate notification sound.
- Stop/Snooze mutates its own valid alarm occurrence and stops a player only when both the alarm and occurrence identities match.
- A replaced macOS schedule rejects actions and default taps from the previous generation.
- macOS Snooze commits the new stored deadline and Snoozed event after registration succeeds.
  Failure retains previous intent and reports Failed.
  Schedule, cancellation, and notification actions share mutation ordering.
  Successful registration also persists the consumed occurrence timestamp; later recurring deliveries remain independent of a pending Snooze.
- Apple registration preserves host categories and supports concurrent schedules with different Stop/Snooze labels.
- Android retention detaches a completed alarm notification from the service lifetime on API 24+, with an ordinary replacement notification on older supported versions.

## Constraints and validation

Keep the federated public model and Pigeon protocol unchanged.
Keep the existing iOS fallback registration/rollback logic and macOS cancellation playback lock guarantees.
Do not raise platform minimum versions or include the pending AGP/Kotlin migration.
Run regressions for failure paths, occurrence ownership, stale actions, delayed registration, and category coexistence.
Injected playback and notification tests establish control flow and platform API requests; they do not establish physical-device audibility or delivery timing.
