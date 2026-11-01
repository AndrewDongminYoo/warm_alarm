# Snooze limit contract

## Problem

A host cannot limit how many times a person snoozes from the alarm notification (#171).
A host can stop offering Snooze on its own ring screen, but the notification keeps the Snooze action on every ring.

- iOS and macOS build every alarm category with both Stop and Snooze, and replace a null `snoozeActionTitle` with "Snooze" (`warm_alarm_ios/.../WarmAlarmDelegate.swift:624-644`, `warm_alarm_macos/.../WarmAlarmDelegate.swift:378-398`).
- Android adds the Snooze action only when `snoozeActionTitle` is non-null (`WarmAlarmForegroundService.kt:403-412`), but `handleSnooze` reschedules the same stored schedule (`:181-206`), so the next ring offers Snooze again and the host never gets to change it.
- `WarmAlarmSnooze` carries only `duration`.

## Scope

Add `WarmAlarmSnooze.maxCount` (`int?`) to the public platform interface:

- Null offers Snooze on every ring, which is the current behavior.
- 0 offers no Snooze action.
- A positive value allows that many snoozes from the notification for one occurrence; the ring after the last allowed snooze has no Snooze action.

Add `WarmAlarmWarningCode.unsupportedSnoozeLimit` for a backend that cannot honor a non-null `maxCount` because the system performs the snooze.

## Counting

The count belongs to one occurrence of one schedule.
It increases on each snooze the plugin performs from the notification, and returns to 0 when:

- a new occurrence rings (not a snoozed ring, and not an Android wake-check retrigger ring);
- the alarm is scheduled again with the same id, or cancelled.

A host that schedules its own snooze ring (for example a one-shot schedule after an in-app Snooze button) passes the number of snoozes left as that schedule's `maxCount`, so the limit holds across both paths.

A Snooze response that arrives when the count has reached `maxCount` (for example from a notification the system retained) does not snooze.

## Platform design

These notes bind the platform releases that follow the interface release.

- **Android.** Persist the count next to `active_snooze_<id>` in `WarmAlarmStore`, and clear it wherever the active snooze is cleared for a new occurrence, a new schedule, a cancel, or `cancelAllAlarms`. `WarmAlarmReceiver` must read whether the ring is a snoozed ring before it clears the active snooze. `buildNotification` omits the Snooze action when the count has reached `maxCount`; `handleSnooze` refuses a snooze past the limit.
- **iOS and macOS (User Notifications).** The next ring's category is fixed when its request is built, so the snooze reschedule decides it. Add a Stop-only category variant that `ownsCategory`, `registerCategories` and the host-delegate proxy accept, distinguished by a userInfo flag and the category identifier. Persist the count in the stored schedule data through the migration-tolerant decoder, so recovery rebuilds the same category. Both Swift copies change, with tests in both.
- **iOS AlarmKit.** The system performs the snooze, and the plugin cannot remove the snooze button from a running alarm. Schedule as today and return `unsupportedSnoozeLimit` when `maxCount` is non-null.

## Constraints

Keep the model backward compatible: `maxCount` is nullable and defaults to null.
The new enum value breaks exhaustive switches, so the interface is released as 0.3.0, and the same merge widens every sibling's interface constraint to `<0.4.0` without moving a lower bound or a sibling version.
No platform reads `maxCount` in the interface release; each platform release raises its interface floor to 0.3.0.
The facade validates that `maxCount` is not negative in its own release.

## Acceptance

- Interface: model and enum tests, Flutter analysis, scoped Dart formatting and Trunk checks pass, and the package workflow passes Pana.
- Each platform: a test that fails before the change shows the Snooze action offered after the limit, and passes afterwards; the existing snooze tests keep passing.
- Facade: a negative `maxCount` is rejected with the same `ArgumentError` shape as a negative snooze duration.
