# Weekly Recurrence Rescheduling — Design Decision

**Date:** 2026-07-11
**Status:** Implemented (native runtime unverified on-device; see Verification)

## Problem

`WarmAlarmRecurrence.weekdays` (a `List<int>` of ISO weekday numbers) was accepted,
persisted, and round-tripped into `WarmAlarmSnapshot` on all three platforms, but no
platform ever re-armed the next occurrence after an alarm fired.
"Weekly recurrence" was effectively a one-shot alarm.
There was no prior spec, plan, or wiki precedent defining the post-fire behavior, so
the semantics below are new precedent for this project.

## Weekday convention

The public field uses **ISO 8601**: `1 = Monday … 7 = Sunday`, matching Dart's
`DateTime.weekday`.
Platform weekday numbering differs and is mapped explicitly:

- Apple `Calendar`/`DateComponents.weekday`: `1 = Sunday … 7 = Saturday`.
  Mapping: `appleWeekday = (iso % 7) + 1` (Mon 1 → 2, … Sun 7 → 1).
- `java.util.Calendar.DAY_OF_WEEK`: `1 = Sunday … 7 = Saturday`.
  Mapping: `iso = (dow == SUNDAY) ? 7 : dow - 1`.

## Dismiss / cancel / snooze contract

- **Dismiss (Stop) ends only the current occurrence.** The series keeps firing on its
  weekdays; the stored schedule is retained.
- **`cancelAlarm(id)` tears down the whole series** — it removes the stored schedule and
  every pending platform trigger for that id.
- **Snooze stays a one-shot** and does not consume or drift the series. It schedules a
  separate transient notification and leaves the recurring triggers untouched.

## Platform implementation (deliberately asymmetric)

An iOS/macOS notification fires even when the app process is dead, so "re-arm on fire"
is unreliable there — the re-arm code would not run. Android `AlarmManager` is
single-shot and _must_ be re-armed, but its fire receiver runs without a Flutter engine.
So:

- **Apple (iOS + macOS):** one native `UNCalendarNotificationTrigger(repeats: true)` per
  selected weekday, matching `DateComponents(weekday, hour, minute)`. Requests are keyed
  `"{id}#{isoWeekday}"`. No re-arm needed; the series survives app termination natively.
  The one-shot (non-recurring) path is unchanged (identifier `"{id}"`).
- **Android:** schedule the first matching occurrence; the fire receiver
  (`WarmAlarmReceiver`) computes the next occurrence (`WarmAlarmRecurrence.nextOccurrence`,
  same time-of-day, strictly after now) and re-arms it, updating the stored
  `scheduledAtMillis` so boot recovery stays correct.

Because the fired notification identifier is `"{id}#{weekday}"` on Apple, the delivered
notification is cleared using the fired request's identifier (threaded into stop/snooze),
while `content.userInfo["alarmId"]` keeps the plain id so the schedule still resolves.

## Known limitations

- **iOS 64 pending-notification cap.** Per-weekday requests multiply pending count by up
  to 7 (e.g. 10 recurring alarms × 7 days = 70 > 64). iOS silently drops the overflow.
  A daily alarm across many ids can exceed the budget.
- **Runtime unverified on-device.** Only the pure weekday math is unit-tested
  (`WarmAlarmRecurrenceTest` on Android; the ISO→Apple mapping on iOS). Whether the
  `repeats: true` trigger and the Android receiver re-arm behave under Doze / app-kill was
  not exercised in-session — validate via CI compile and on-device before release.
