# Android alarm ID contract

## Problem and decision

[Issue #72](https://github.com/AndrewDongminYoo/warm_alarm/issues/72) identifies alarm IDs that alias after narrowing to a `PendingIntent` request code and an accepted `-1` ID that receivers silently discard.
Android supports signed 32-bit alarm IDs, from `-2147483648` through `2147483647`, inclusive.
Negative IDs, including `-1`, are valid; a missing intent extra is not an alarm ID.
Other platforms and the public integer model remain unchanged.

The existing regular-alarm identity must remain cancellable after an update.
Full 64-bit identity support would require recovering already-aliased legacy registrations, so it is outside this correction.
Oracle's model-boundary precedent (`wiki/concepts/model-boundary-rule.md`, backed by `raw/sources/warm_alarm/CLAUDE.md`) confirms that this platform-specific policy belongs behind the public model boundary.
No direct project precedent defines the ID range or legacy migration.

## Contract

1. Scheduling or individually cancelling an out-of-range ID returns `INVALID_ALARM_ID` before changing storage, services, notifications, or alarm registrations.
2. Regular scheduling, snooze/retrigger scheduling, startup recovery, and boot recovery use the same checked `PendingIntent` factory.
3. Receivers and service commands distinguish a missing extra from `-1` and reject out-of-range IDs before acting on alarm state.
4. Unsupported stored or delivered IDs produce a failed event with `invalidArguments`; recovery does not arm them or touch an aliased supported registration.
5. Unsupported stored records remain available for inspection; `cancelAllAlarms` clears those records without looking up their truncated IDs.
6. Regular and wake-check identities preserve their existing request codes and actions for supported IDs; regular alarms remain data-less and retriggers retain their URI.
7. Stop and Snooze action identities include the full supported ID in a URI, so multiplication-based request-code collisions cannot retarget another alarm's action.

The Android [PendingIntent contract](https://developer.android.com/reference/android/app/PendingIntent) excludes extras from identity comparison.
Distinct actions separate regular delivery, wake checks, and dismissal; URI data separates retriggers and notification actions.

## Acceptance

- Regressions exercise `Int.MIN_VALUE`, `-1`, `0`, and `Int.MAX_VALUE`, reject values just outside the range and long extremes, and cover IDs separated by `2^32`.
- Invalid scheduling and cancellation tests observe zero platform or storage side effects.
- Service and receiver tests deliver `-1` through real dispatch and confirm that missing or invalid IDs do not act on another alarm.
- Recovery tests show unsupported records produce failures while supported records are restored through the common factory.
- Real-framework instrumented tests verify lookup and cancellation isolation, legacy regular lookup compatibility, and Stop/Snooze action isolation.
- New JVM regressions fail on the original behavior before the fix; native and Dart tests, Flutter analysis, formatting, Trunk, and current-head CI pass.

## Non-goals and limits

Do not migrate or reconstruct already-aliased out-of-range operating-system registrations, widen the wire format, add dependencies, or change Apple behavior.
The existing notification-ID namespace and stale action semantics are separate concerns.
JVM boundary mocks establish dispatch and side-effect ordering; instrumented tests establish framework identity, not physical alarm timing or sound.
There is no visual approval requirement.
