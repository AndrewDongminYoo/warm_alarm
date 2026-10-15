# Apple notification cancellation ownership

## Problem and contract

[Issue #76](https://github.com/AndrewDongminYoo/warm_alarm/issues/76) identifies an app-wide notification deletion in both Apple implementations of `cancelAllAlarms()`.
Cancel pending warm_alarm requests while preserving notifications scheduled by the host or other plugins.
Keep the public API, generated bindings, notification identifiers, and existing AlarmKit failure behavior unchanged.

## Ownership and ordering

Read pending requests and select the existing `WARM_ALARM` notification category, including primary, recurring, snoozed, fallback, and orphan requests with no stored schedule.
Also remove the exact reserved `warm_alarm_kill_warning_notif` identifier, which does not carry the alarm category.
Do not infer ownership from a numeric identifier, identifier prefix, or an `alarmId` payload alone.
Keep the mutation queue occupied until the pending-request read, scoped removal submission, and platform reply finish.
On iOS, a failed AlarmKit cancellation must retain notification requests and stored schedules as before.
Delivered notifications and playback behavior retain their current contract.

## Verification

1. Exercise cancellation with mixed host and plugin pending requests on each platform.
2. Verify that primary, recurring, fallback, snoozed, orphan, and kill-warning requests are removed, as applicable to each platform.
3. Verify that unrelated host requests survive, including numeric IDs and payloads that resemble alarm data.
4. Verify that a delayed pending read cannot complete cancellation or release the mutation queue early.
5. Verify the iOS AlarmKit failure path preserves local state.
6. Run the native regression with the broad-removal behavior and observe failure, then run the corrected behavior and relevant suites.

The notification service boundary may use an in-memory transport with real `UNNotificationRequest` values; plugin cancellation and queue behavior must execute unchanged.
Local iOS host builds are constrained by disk capacity, so hosted native tests remain required before merge readiness.
There is no product visual change and no device installation requirement.
Oracle returned `[no precedent found]` for the scoped cancellation topics.
