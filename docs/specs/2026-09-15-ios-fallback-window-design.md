<!-- cspell:words Mirae -->

# iOS Fallback Window Design

## Status

Approved for implementation on 2026-09-15.

Linear issue: [AND-170](https://linear.app/andrewdongminyoo/issue/AND-170/ios-%ED%8F%B4%EB%B0%B1-%EC%95%8C%EB%A6%BC%EC%9D%B4-3%EB%B6%84-%EB%A7%8C%EC%97%90-%EB%81%8A%EA%B2%A8-%EC%82%AC%EC%9A%A9%EC%9E%90%EA%B0%80-%EC%9D%91%EB%8B%B5%ED%95%98%EC%A7%80-%EC%95%8A%EC%95%84%EB%8F%84-%EC%95%8C%EB%9E%8C%EC%9D%B4-%ED%8F%AC%EA%B8%B0%EB%90%A8).

## Problem

The `warm_alarm_ios` User Notifications backend schedules one primary request at T and six fallback requests at 30-second intervals.
The last fallback therefore fires at T+3 minutes.
This behavior blocks the iOS fallback validation in AND-50.

Mirae's approved 2026-02-18 fallback design describes ten notification attempts at T through T+4 minutes 30 seconds and calls all ten attempts fallbacks.
The plugin now uses different terms: it treats the T request as the primary request and counts only later requests as fallbacks.
AND-170 identifies the current six fallbacks as a three-minute window and requests the approved five-minute policy.
This design resolves the terminology mismatch by defining exact request times.

## Decision

For every occurrence that uses the User Notifications backend, schedule:

- One primary request at T.
- Ten one-shot fallback requests at T+30 seconds through T+5 minutes.
- Eleven total requests when the pending-request budget can hold the full chain.

Set `fallbackCount` to `10` and keep `fallbackIntervalMillis` at `30_000`.
The policy horizon is the last fallback at T+5 minutes.
The primary request does not count toward `fallbackCount`.

This definition supersedes the older Mirae document only where that document counted the T request as one of ten fallbacks and ended at T+4 minutes 30 seconds.
It preserves the approved cadence and makes the five-minute horizon explicit.

## Scope

### In scope

- Apply the ten-fallback policy to one-shot, recurring, recovery, and snooze request construction in `warm_alarm_ios`.
- Preserve the existing identifier format from `#fallback#1` through `#fallback#10`.
- Preserve capacity selection, replacement, rollback, cancellation, delivered-notification cleanup, occurrence identity, and stale-action suppression for the longer identifier range.
- Update iOS package documentation and release metadata.
- Publish the iOS implementation package and refresh Mirae's hosted resolution after separate external-impact approval.

### Out of scope

- Do not change AlarmKit scheduling, audio, authorization, or observation.
- Do not emulate unbounded ringing with repeating User Notifications requests.
- Do not change the public Dart API, Pigeon schemas, Android behavior, or macOS behavior.
- Do not restore Mirae's legacy Dart-owned fallback scheduler.
- Do not change Linear states before the required automated and device evidence exists.

## Request Construction

All User Notifications request builders use the same policy constants.

| Request     | Identifier                                       | Fire time    |
| ----------- | ------------------------------------------------ | ------------ |
| Primary     | `<alarmId>` or the existing recurring identifier | T            |
| Fallback 1  | `<alarmId>#fallback#1`                           | T+30 seconds |
| Fallback 2  | `<alarmId>#fallback#2`                           | T+1 minute   |
| Fallback 10 | `<alarmId>#fallback#10`                          | T+5 minutes  |

One-shot and recurring fallback requests remain non-repeating `UNCalendarNotificationTrigger` requests.
Snooze fallbacks remain non-repeating `UNTimeIntervalNotificationTrigger` requests.
The request content and occurrence metadata remain unchanged except that ordinals now extend through `10`.

## Pending-Request Capacity

iOS limits the app to 64 pending notification requests.
The existing capacity policy remains authoritative:

- Preserve every primary and per-weekday recurring request before any fallback.
- Reserve the kill-warning slot when that warning is configured.
- Select the longest ordered fallback prefix that fits the remaining capacity.
- Return the existing warning when one or more of the ten fallbacks are omitted.
- Reject scheduling without replacing the previous schedule when the core requests do not fit.

The five-minute policy is therefore the full-capacity target, not a guarantee when other pending app requests consume the system budget.
The warning must report the selected count out of ten.

## Recovery and Lifecycle

Recovery treats the fallback window as active while the T+5-minute request is still in the future.
At or after T+5 minutes, the occurrence has no future fallback to recover.
Recovery recreates only missing future fallbacks and keeps their original 30-second slots.

Replacement, Stop, Snooze, and cancellation must recognize identifiers through `#fallback#10`.
They must remove or restore the same logical prefix that the current lifecycle operation owns.
Delivered-notification cleanup must also include every fallback identifier through `#fallback#10`.

## Failure Handling

The change does not add a new fallback strategy.
Existing behavior handles the relevant failures:

- A core-capacity failure preserves the previous schedule and returns `pending-notification-limit`.
- A partial fallback selection succeeds with the existing capacity warning.
- A partial registration failure uses the existing rollback path.
- A recovery pass does not recreate expired fallback slots.

## Test Contract

Native XCTest coverage must prove these properties:

- A full one-shot chain contains one primary request and ten fallbacks.
- The fallback identifiers are ordered from `#fallback#1` through `#fallback#10`.
- The last fallback fires at T+5 minutes for one-shot, recurring, and snooze paths.
- Occurrence metadata uses one stable token and ordinals `0...10`.
- Capacity selection preserves core requests and chooses the longest fallback prefix.
- Capacity warnings report the selected fallback count out of ten.
- Recovery restores only the future subset through T+5 minutes and considers the chain expired at that boundary.
- Cancellation, rollback, Stop, Snooze, and delivered-notification cleanup recognize `#fallback#10`.

The first new policy test must fail against `fallbackCount = 6` by observing six fallbacks and a T+3-minute last fire time.
This Red result is required before changing the production constant.

## Release and Acceptance

The implementation release is `warm_alarm_ios 0.1.9` unless the package version changes before execution.
The published `warm_alarm 0.1.4` facade already accepts compatible `warm_alarm_ios` versions through its current caret constraint, so this change does not require a facade release.
Mirae keeps its direct `warm_alarm` constraint and refreshes `pubspec.lock` to the published iOS implementation.

Automated tests prove request construction and lifecycle behavior.
They do not prove audible delivery over five minutes on a real device.
AND-170 remains incomplete until a physical-device run demonstrates that the effective backend is User Notifications, the full chain reaches T+5 minutes, and Stop removes the remaining pending requests.
If no compatible device can exercise the User Notifications backend, record the automated delivery as complete and keep the device acceptance and AND-50 blocker open.

## Approval Gate

The operator approved these exact semantics on 2026-09-15: one primary request plus ten fallbacks, with the last fallback at T+5 minutes.
