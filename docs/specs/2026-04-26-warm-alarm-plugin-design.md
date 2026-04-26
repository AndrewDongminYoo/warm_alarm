# Warm Alarm Plugin Design

## Status

Approved design direction, pending final spec review before implementation planning.

## Context

This repository is already a Flutter federated plugin workspace with these packages:

- `warm_alarm`
- `warm_alarm_platform_interface`
- `warm_alarm_android`
- `warm_alarm_ios`
- `warm_alarm_macos`

Today the codebase is still the generated template skeleton. The public Dart surface only exposes `getPlatformName()`. Each platform package already has a minimal Pigeon HostApi for the same call, but there is no real alarm domain implementation yet.

The product goal is not a generic reminder plugin. It is an alarm experience centered on user-recorded voice playback, alarm dismissal, follow-up wake confirmation, and explicit handling of platform capability gaps.

## Problem Statement

We need to replace the template plugin API with a real cross-platform alarm architecture that:

- supports Android, iOS, and macOS from one Dart package family
- uses typed native communication instead of ad hoc `MethodChannel` maps
- avoids freezing the wrong public API too early
- preserves room for Android-rich behavior without over-promising parity on Apple platforms

## Goals

- Use Pigeon for native communication.
- Keep public Dart models separate from transport-layer wire models.
- Stabilize a small, honest public API first.
- Support explicit capability and unsupported-state reporting.
- Validate the full alarm loop on Android first.

## Non-Goals

- Publishing a fully generic alarm package in the first release.
- Guaranteeing identical scheduling, playback, or wake semantics across all platforms.
- Exposing Live Activity, background audio, or wake-check flows as fully stable cross-platform public domains in v1.

## Key Findings From Repo And Platform Research

### Repository findings

- The current workspace shape is already correct for a federated plugin.
- There is no existing alarm scheduling, playback, notification, permission, or wake-check implementation.
- The current public interface is small enough that we can still choose the right boundary before real behavior ships.

### External platform findings

- Android exact alarms are permission-gated and require explicit capability checks.
- iOS supports scheduled local notifications, but arbitrary background wake-and-play alarm semantics are much more constrained than Android.
- macOS should be treated as a related desktop alarm/reminder target, not assumed to have mobile-alarm parity.
- Pigeon is appropriate as internal transport code and should not define the public API.

## Decision

Use the existing `warm_alarm` federated plugin workspace and evolve it into the alarm product architecture.

Do **not** introduce five first-class public APIs immediately.

Instead:

- keep the **public API narrow** in the first real release
- allow **internal domain separation** for scheduler, playback, wake-check, permissions, and activity concerns
- keep **Pigeon private** to platform implementation packages

## Recommended Public API Shape

The first stable public surface should be centered on alarm scheduling plus explicit platform inspection.

The API must expose three separate concepts:

- `getCapabilities()` — what this platform and OS version can support in principle
- `getPermissionState()` — what the user or system currently allows
- `getReadiness()` — whether the plugin can currently schedule and deliver the best available alarm behavior

Representative operations:

- `scheduleAlarm(WarmAlarmSchedule schedule)`
- `cancelAlarm(int id)`
- `cancelAllAlarms()`
- `getScheduledAlarms()`
- `getAlarmState(int id)`
- `getCapabilities()`
- `getPermissionState()`
- `getReadiness()`
- `events`

This keeps the public contract honest while still allowing rich internal behavior.

An approximate public shape is:

```dart
abstract interface class WarmAlarmPlatform {
  Future<WarmAlarmCapabilities> getCapabilities();

  Future<WarmAlarmPermissionState> getPermissionState();

  Future<WarmAlarmReadiness> getReadiness();

  Future<void> scheduleAlarm(WarmAlarmSchedule schedule);

  Future<void> cancelAlarm(int id);

  Future<void> cancelAllAlarms();

  Future<List<WarmAlarmSnapshot>> getScheduledAlarms();

  Stream<WarmAlarmEvent> get events;
}
```

## Semantics Of Schedule Success

`scheduleAlarm` success means the platform implementation accepted the best available scheduling request.

It does not guarantee identical behavior across Android, iOS, and macOS.

In particular:

- Android may support exact alarms, full-screen presentation, foreground playback, and retrigger flows when permissions allow.
- iOS scheduling primarily means local notification scheduling unless the app is already active or the user interacts with the notification.
- macOS scheduling primarily means desktop notification or reminder behavior and optional playback while the app can run.

Apps must use capabilities, permission state, readiness, and lifecycle events to determine the actual level of alarm reliability.

## Internal Architecture

Internally, implementation packages may still be organized by responsibility:

- scheduler
- playback
- wake-check
- permissions
- activity or live activity integration

This is an implementation detail, not an immediate public API promise.

## Package Responsibilities

### `warm_alarm`

- app-facing package
- exports stable public models and the main facade
- does not export generated Pigeon classes

### `warm_alarm_platform_interface`

- owns the abstract platform contract
- owns stable public value types shared across implementations
- remains hand-written

### `warm_alarm_android`

- owns Android-specific Pigeon schema and generated bindings
- implements Android alarm scheduling, playback, exact-alarm checks, and later wake-check behavior
- is the first platform to receive end-to-end validation

### `warm_alarm_ios`

- owns iOS-specific Pigeon schema and generated bindings
- implements honest notification-driven behavior with explicit unsupported results where Android-only semantics do not translate

### `warm_alarm_macos`

- owns macOS-specific Pigeon schema and generated bindings
- implements desktop-appropriate notification and playback behavior
- does not imply mobile-style alarm guarantees unless validated

## Model Boundary Rule

Two model layers must exist:

### Public models

- hand-written
- designed for developer ergonomics and semver stability
- exported from `warm_alarm` and defined in `warm_alarm_platform_interface`

### Wire models

- Pigeon DTOs used only for Flutter-to-native and native-to-Flutter transport
- generated inside platform implementation packages
- not exported publicly

This prevents transport concerns from locking the public API.

## Public Model Draft

The implementation plan should begin from hand-written public models at roughly this level of specificity.

```dart
final class WarmAlarmSchedule {
  const WarmAlarmSchedule({
    required this.id,
    required this.scheduledAt,
    required this.notification,
    required this.audio,
    this.recurrence,
    this.snooze,
  });

  final int id;
  final DateTime scheduledAt;
  final WarmAlarmNotification notification;
  final WarmAlarmAudio audio;
  final WarmAlarmRecurrence? recurrence;
  final WarmAlarmSnooze? snooze;
}
```

```dart
final class WarmAlarmAudio {
  const WarmAlarmAudio({
    this.filePath,
    this.assetPath,
    this.loop = true,
    this.volume,
    this.fadeInDuration,
    this.vibrate = true,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final Duration? fadeInDuration;
  final bool vibrate;
}
```

```dart
final class WarmAlarmNotification {
  const WarmAlarmNotification({
    required this.title,
    required this.body,
    this.stopActionTitle,
    this.snoozeActionTitle,
  });

  final String title;
  final String body;
  final String? stopActionTitle;
  final String? snoozeActionTitle;
}
```

```dart
final class WarmAlarmCapabilities {
  const WarmAlarmCapabilities({
    required this.exactScheduling,
    required this.notificationScheduling,
    required this.backgroundAudioPlayback,
    required this.fullScreenPresentation,
    required this.wakeCheck,
    required this.liveActivity,
  });

  final WarmAlarmSupportStatus exactScheduling;
  final WarmAlarmSupportStatus notificationScheduling;
  final WarmAlarmSupportStatus backgroundAudioPlayback;
  final WarmAlarmSupportStatus fullScreenPresentation;
  final WarmAlarmSupportStatus wakeCheck;
  final WarmAlarmSupportStatus liveActivity;
}
```

```dart
enum WarmAlarmReadinessLevel {
  ready,
  limited,
  blocked,
  unsupported,
}
```

Additional value types such as `WarmAlarmPermissionState`, `WarmAlarmReadiness`, `WarmAlarmSnapshot`, `WarmAlarmRecurrence`, and `WarmAlarmSnooze` should be hand-written beside these models during planning.

## Event Model Draft

Phase 1 should expose lifecycle events for the core alarm loop without freezing wake-check configuration into the public schedule model.

Initial public event types:

```dart
sealed class WarmAlarmEvent {
  const WarmAlarmEvent({required this.alarmId, required this.occurredAt});

  final int alarmId;
  final DateTime occurredAt;
}

final class WarmAlarmScheduled extends WarmAlarmEvent {}

final class WarmAlarmFired extends WarmAlarmEvent {}

final class WarmAlarmStopped extends WarmAlarmEvent {}

final class WarmAlarmSnoozed extends WarmAlarmEvent {
  final Duration duration;
}

final class WarmAlarmFailed extends WarmAlarmEvent {
  final WarmAlarmFailure failure;
}
```

Phase 2 may extend the public event stream with:

```dart
final class WarmAlarmWakeCheckShown extends WarmAlarmEvent {}

final class WarmAlarmWakeCheckDismissed extends WarmAlarmEvent {}

final class WarmAlarmWakeCheckExpired extends WarmAlarmEvent {}

final class WarmAlarmRetriggered extends WarmAlarmEvent {}
```

This keeps wake-check experimentation possible internally before its scheduling model is promoted into the stable public request type.

## Pigeon Boundary Rule

Use:

- `@HostApi` for Flutter to native requests such as schedule, cancel, stop, snooze, or capability queries
- `@FlutterApi` for native to Flutter callbacks such as alarm fired, stopped, snoozed, wake-check expired, or failure events

Pigeon files should stay self-contained and local to each implementation package.

## Unsupported Versus Failed Behavior

Unsupported behavior is not a runtime failure.

- `unsupported`: the platform or OS does not provide the requested capability
- `limited`: the platform supports a reduced version of the behavior
- `permissionDenied`: the capability may exist, but the user or system has not granted access
- `failed`: the implementation attempted the behavior and it failed unexpectedly

The plugin must not silently no-op unsupported behavior.

Recommended public distinctions:

```dart
enum WarmAlarmSupportStatus {
  supported,
  limited,
  unsupported,
  unknown,
}
```

```dart
enum WarmAlarmFailureCode {
  unknown,
  invalidArguments,
  permissionDenied,
  exactAlarmUnavailable,
  notificationUnavailable,
  audioFileNotFound,
  audioPlaybackFailed,
  schedulingFailed,
  platformInternalError,
}
```

## Why Not Split The Public API Now

Creating public peer APIs such as `AlarmSchedulerApi`, `AlarmPlaybackApi`, `WakeCheckApi`, `AlarmPermissionApi`, and `AlarmActivityApi` immediately would create semver pressure before the real cross-platform semantics are proven.

Main risks:

- Android behavior could accidentally define the meaning of every API.
- iOS and macOS would appear to promise parity they do not yet support.
- Live Activity and wake-check behavior would be frozen before their platform boundaries are validated.

The repo is early enough that we should avoid freezing the wrong abstraction.

## MVP Scope

### Phase 1

- replace `getPlatformName()` with the first real public alarm facade
- add separate capability, permission-state, and readiness reporting
- implement Android scheduling end to end
- provide explicit unsupported or reduced behavior on iOS and macOS
- wire native-to-Dart lifecycle events through `@FlutterApi`

#### Phase 1A: API replacement and stubs

- remove or deprecate `getPlatformName()`
- add hand-written public models and platform interface methods
- add per-platform stub implementations with accurate `supported`, `limited`, or `unsupported` reporting
- generate Pigeon schemas and bindings without publicly exporting wire DTOs

Definition of done:

- example app can call schedule, cancel, `getCapabilities()`, `getPermissionState()`, and `getReadiness()`
- Android, iOS, and macOS all build successfully
- generated Pigeon DTOs are not publicly exported
- unsupported and limited states are surfaced explicitly per platform

#### Phase 1B: Android alarm proof

- add exact-alarm permission checks
- implement native alarm scheduling and event delivery
- wire local file audio playback and stop or snooze actions

Definition of done:

- an alarm can fire while the app is backgrounded
- local file audio playback works in the validated Android path
- stop and snooze arrive on the Dart event stream
- permission-denied or unavailable cases return explicit failure or blocked readiness states

#### Phase 1C: Apple reduced behavior

- implement iOS local notification scheduling
- implement macOS notification scheduling
- return accurate limited or unsupported capability states
- connect notification interaction events where available

Definition of done:

- Apple platforms do not promise Android-equivalent wake behavior
- the public API exposes which behaviors are limited or unsupported
- `scheduleAlarm` success semantics match the documented contract

### Phase 2

- add Android wake-check flow
- refine Apple-platform notification and playback behavior
- expand state reporting based on real platform behavior

### Phase 3

- consider promoting additional public domains only after stable semantics exist
- evaluate whether playback or activity should become independently public features

## Capability Principles

The API must expose capability truth instead of assuming all platforms can do the same thing.

Examples:

- exact alarm available or unavailable
- notification permission granted or denied
- full-screen experience supported or unsupported
- background playback available, limited, or unsupported
- live activity available, unavailable, or unsupported

Unsupported must be explicit, not a silent no-op.

Readiness must remain a separate product-facing concept. Capability says what the platform can do in principle, permission state says what access is currently granted, and readiness says whether the plugin can currently deliver the best available alarm behavior for this device state.

## Android-First Validation Requirement

Before expanding the public API surface, validate this full loop on Android:

1. schedule an alarm
2. fire while app is backgrounded
3. play the selected recording or fallback audio
4. deliver a stop or snooze event back to Dart
5. schedule wake-check follow-up behavior
6. retrigger when configured and unacknowledged

This loop is the product-critical proof point.

## Alternatives Considered

### Option A: split five public APIs immediately

Pros:

- clean conceptual separation
- close match to future internal architecture

Cons:

- over-promises cross-platform maturity
- adds semver burden too early
- likely to freeze Android-shaped semantics into public contracts

### Option B: single large settings object and one monolithic alarm API

Pros:

- quick to ship initially

Cons:

- mixes unrelated platform concerns
- becomes hard to evolve cleanly
- pushes transport structure into product API design

### Chosen option: narrow public facade with internal domain split

This gives the best balance of honesty, evolvability, and product focus.

## Risks And Mitigations

### Risk: MVP becomes secretly Android-specific

Mitigation:

- document capability differences explicitly
- avoid names that imply uniform wake behavior everywhere

### Risk: Pigeon leaks into public API

Mitigation:

- keep generated files under `src/` in implementation packages only
- define public models by hand in the platform interface

### Risk: Apple platforms look feature-complete on paper but not in behavior

Mitigation:

- return explicit unsupported or limited capability states
- delay promotion of Apple-specific UX features into the stable contract

## Implementation Planning Constraints

The implementation plan must follow these rules:

- no public export of generated Pigeon DTOs
- no assumption of cross-platform feature parity without validation
- Android first for end-to-end behavioral proof
- capability-first error and support reporting
- public API additions should be conservative until real semantics are tested

## Acceptance Criteria For Design Phase

This design is complete when:

- the repo continues using the existing federated plugin workspace
- the first implementation plan targets a narrow public facade instead of five public domains
- public and wire model separation is preserved
- platform asymmetry is represented explicitly
- Android-first validation is treated as the gating proof of the product loop
