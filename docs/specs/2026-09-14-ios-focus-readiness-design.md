<!-- cspell:words Mirae -->

# iOS Focus Readiness Design

## Status

Approved for implementation on 2026-09-14.

Linear issue: [AND-148](https://linear.app/andrewdongminyoo/issue/AND-148/ios-focus-%EC%95%8C%EB%9E%8C-%EC%A0%84%EB%8B%AC%EA%B3%BC-%EA%B6%8C%ED%95%9C-%EC%A4%80%EB%B9%84-%EC%83%81%ED%83%9C%EB%A5%BC-%EC%9D%BC%EC%B9%98%EC%8B%9C%ED%82%B4).

## Problem

The User Notifications backend creates audible alarm notifications, but it does not request or set the time-sensitive delivery level.
Its readiness snapshot also reduces notification authorization to one Boolean value.
As a result, the public API cannot distinguish full authorization from provisional authorization, disabled alerts, disabled sounds, or disabled Time Sensitive Notifications.

The AlarmKit backend has a different delivery contract.
When AlarmKit is authorized and owns the effective schedule, notification settings must not downgrade its readiness because the system alarm does not depend on User Notifications delivery.

Mirae no longer schedules new Dart-owned iOS fallback notifications.
The `warm_alarm_ios` User Notifications backend owns primary and fallback notification requests.
Mirae retains cleanup code only for notifications that an older app version scheduled.

## Goals

- Request Time Sensitive Notifications together with alert and sound authorization on iOS 15 and later.
- Mark every alarm notification that uses the User Notifications backend as time-sensitive on iOS 15 and later.
- Expose the current authorization, alert, sound, and time-sensitive settings through the public readiness model.
- Keep existing callers source-compatible.
- Make notification-settings combinations deterministic in native tests through an injected reader.
- Preserve AlarmKit readiness when AlarmKit is authorized and owns the effective schedule.
- Document the fields that a host uses to provide settings guidance.

## Non-goals

- Do not add Critical Alerts or request its entitlement.
- Do not change AlarmKit scheduling, sound preparation, or observation.
- Do not restore Dart-owned fallback scheduling in Mirae.
- Do not change the six-notification fallback window tracked by AND-170.
- Do not add UI copy to Mirae in this delivery.
- Do not change Android or macOS notification behavior.

## Public API

Add a source-compatible optional field to `WarmAlarmReadiness`:

```dart
final WarmAlarmNotificationSettings? notificationSettings;
```

The constructor default is `null` so existing consumers and existing platform implementations continue to compile.
Android, macOS, and the default method-channel implementation return `null` until those platforms provide equivalent data.

Add this public authorization enum:

```dart
enum WarmAlarmNotificationAuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}
```

Add this immutable settings model:

```dart
final class WarmAlarmNotificationSettings {
  const WarmAlarmNotificationSettings({
    required this.authorizationStatus,
    required this.alertsEnabled,
    required this.soundsEnabled,
    required this.timeSensitiveEnabled,
  });

  final WarmAlarmNotificationAuthorizationStatus authorizationStatus;
  final bool alertsEnabled;
  final bool soundsEnabled;
  final bool? timeSensitiveEnabled;
}
```

`timeSensitiveEnabled` is `null` before iOS 15 because that setting is unavailable.
The other Boolean fields are `true` only when the corresponding `UNNotificationSetting` is `.enabled`.

The existing `reasons` list stays compatible.
Denied or undetermined notification authorization continues to add `notificationPermissionDenied`.
The new `notificationSettings` value carries the more precise states without adding cases to the published `WarmAlarmReadinessReason` enum.
This avoids making the exhaustive mapping switches in already-published platform packages invalid when the platform-interface package updates.

## Wire Contract

Add iOS-only Pigeon types that mirror the public model:

```dart
enum WarmAlarmNotificationAuthorizationStatusWire {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}

class WarmAlarmNotificationSettingsWire {
  const WarmAlarmNotificationSettingsWire({
    required this.authorizationStatus,
    required this.alertsEnabled,
    required this.soundsEnabled,
    required this.timeSensitiveEnabled,
  });

  final WarmAlarmNotificationAuthorizationStatusWire authorizationStatus;
  final bool alertsEnabled;
  final bool soundsEnabled;
  final bool? timeSensitiveEnabled;
}
```

Add nullable `notificationSettings` to the iOS `WarmAlarmReadinessWire` type.
Regenerate the iOS Dart and Swift Pigeon outputs from `warm_alarm_ios/pigeons/messages.dart`.
Do not edit generated files directly.

Android and macOS Pigeon schemas do not change because the new public field has a `null` default and those implementations do not produce the iOS settings snapshot.

## Native Settings Reader

Introduce an internal value type that contains only the notification settings required by the readiness calculation.
Introduce a `NotificationSettingsReader` closure on `WarmAlarmPlugin` and default it to `notificationCenter.getNotificationSettings` plus a conversion to the internal value.
Tests inject the closure and supply each settings combination without constructing `UNNotificationSettings`.

Introduce an internal `NotificationAuthorizationRequester` closure whose default calls `requestAuthorization` on the injected `notificationCenter`.
Inject the time-sensitive availability decision so tests can exercise both request-option paths through `requestNotificationPermission` on one simulator.

The plugin must use its injected `notificationCenter` for authorization requests and settings reads.
It must not call `UNUserNotificationCenter.current()` from these paths.

## Authorization Request

The request options are:

- iOS 13 and iOS 14: `.alert` and `.sound`.
- iOS 15 and later: `.alert`, `.sound`, and `.timeSensitive`.

The method continues to return the post-request remediation snapshot.
An authorization error continues to fail the method.
Native tests call `requestNotificationPermission` through an injected requester and assert the exact options for supported and unsupported availability states.
A helper-only assertion is not sufficient because it would not prove that the public method uses those options.

Time Sensitive Notifications are a host-target capability, not a plugin entitlement.
Each iOS host must enable the Time Sensitive Notifications capability and include `com.apple.developer.usernotifications.time-sensitive` with a Boolean `true` value in its signed entitlements.
The package README documents this requirement, and the example iOS target demonstrates it.
Mirae's development, staging, and production Runner entitlement files already contain this key.

## Notification Content

`WarmAlarmDelegate.makeContent` is the single alarm-content factory for User Notifications primary, recurrence, recovery, snooze, and fallback requests.
Set `content.interruptionLevel = .timeSensitive` there on iOS 15 and later.

Do not set a time-sensitive level on kill-warning notifications because they are lifecycle warnings, not alarm occurrences.
Do not change sound selection or category identifiers.

## Readiness Rules

The settings snapshot is always attached to an iOS readiness result.
The effective scheduling backend determines whether the settings affect the readiness level.

| Effective backend          | Authorization and settings            | Level     | Existing reasons                                                                                       |
| -------------------------- | ------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| AlarmKit                   | AlarmKit authorized                   | `ready`   | none                                                                                                   |
| AlarmKit selection pending | AlarmKit not determined               | `limited` | `unknown`                                                                                              |
| User Notifications         | denied or not determined              | `blocked` | `notificationPermissionDenied`, `backgroundExecutionLimited`                                           |
| User Notifications         | authorized, provisional, or ephemeral | `limited` | `backgroundExecutionLimited`, plus `exactAlarmPermissionDenied` when AlarmKit is configured and denied |

For a User Notifications result, hosts inspect `notificationSettings` in addition to `level` and `reasons`.
Provisional authorization, disabled alerts, disabled sounds, or disabled Time Sensitive Notifications require notification-settings guidance even though the existing compatibility reason stays `backgroundExecutionLimited`.
On iOS, `openReadinessSettings(backgroundExecutionLimited)` opens the app notification settings page so hosts can use the existing handoff for these granular states.
Hosts pass `backgroundExecutionLimited` only when the settings snapshot needs notification guidance.
When an exact-alarm reason and a granular notification issue coexist, hosts prioritize `backgroundExecutionLimited` instead of blindly passing `reasons.first`.
When the granular notification settings are healthy, hosts ignore `backgroundExecutionLimited` for notification remediation and select the first other supported reason, if any.

`notificationsGranted` remains `true` for `.authorized`, `.provisional`, and `.ephemeral` because the OS has granted a notification authorization state.
It remains `false` for `.denied`, `.notDetermined`, and unknown states.

## Host Contract

The `warm_alarm` facade exposes the new model through its existing `getReadiness`, remediation, and schedule-result APIs.
The example and README describe these host decisions:

- Full authorization with alerts, sounds, and Time Sensitive Notifications enabled needs no settings guidance.
- Provisional authorization needs guidance to grant full notification authorization.
- Disabled alerts, sounds, or Time Sensitive Notifications need guidance to open notification settings.
- A host target must include the Time Sensitive Notifications entitlement before it can rely on Focus breakthrough behavior.
- A `null` snapshot means that the current platform implementation does not report granular notification settings.

Mirae receives the new fields after it updates its hosted `warm_alarm` constraint and lockfile.
Its current degraded-readiness logging automatically records the existing level and reason list.
No new fallback scheduling or presentation-layer workflow is part of AND-148.

## Test Strategy

Follow Red, Green, Refactor for each behavior.

Native iOS tests must cover:

- alarm content uses `.timeSensitive` on supported iOS versions;
- `requestNotificationPermission` passes `.timeSensitive` through the injected authorization boundary only on supported iOS versions;
- the injected reader drives authorized, provisional, ephemeral, denied, not-determined, unknown, alert-disabled, sound-disabled, and time-sensitive-disabled snapshots;
- AlarmKit-authorized readiness remains `ready` for every notification settings combination;
- `backgroundExecutionLimited` maps to the notification settings handoff on iOS;
- the notification-settings URL selector covers both the iOS 16-specific URL and the earlier app-settings fallback;
- User Notifications readiness follows the table above.

Dart tests must cover:

- the new public model and the nullable constructor default;
- every iOS wire authorization status maps to the public status;
- `getReadiness`, remediation results, and schedule results preserve the settings snapshot;
- the example selects notification remediation from the granular settings instead of using list order;
- Android, macOS, and default implementations still compile and return their existing readiness contract.

Host configuration verification must prove that the example Runner entitlement file contains `com.apple.developer.usernotifications.time-sensitive = true` and that every Runner build configuration uses that file.
The Mirae adoption stage must verify the same key in its development, staging, and production Runner entitlement files before the physical Focus pass.

Generated-output verification must run after the Pigeon input changes.
The focused native and Dart suites must pass before the workspace-wide checks.

## Package Delivery

The delivery uses the repository publish order:

1. Publish `warm_alarm_platform_interface 0.1.3` with the additive public model.
2. Publish `warm_alarm_ios 0.1.8` with the native behavior, iOS wire mapping, and an interface constraint of `^0.1.3`.
3. Publish `warm_alarm 0.1.4` with minimum constraints of `warm_alarm_ios ^0.1.8` and `warm_alarm_platform_interface ^0.1.3`.
4. Update Mirae to `warm_alarm ^0.1.4`, regenerate `pubspec.lock`, and run its declared Flutter gates.
5. Verify Focus delivery and settings states on the registered iPhone, then record the result in AND-50 and AND-148.

Each publish stage is a separate merge and tag.
The next stage starts only after pub.dev exposes the required preceding version.

## Acceptance Criteria

- The public readiness result distinguishes all authorization and delivery settings named in AND-148.
- Existing platform packages and consumers remain source-compatible with the additive interface release.
- Every User Notifications alarm request uses the time-sensitive interruption level where the OS supports it.
- Permission requests include Time Sensitive Notifications where the OS supports it.
- AlarmKit readiness does not regress.
- Focus and settings combinations have failing-first automated tests and a recorded physical-device observation.
