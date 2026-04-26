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

The first stable public surface should be centered on alarm scheduling plus capabilities/state.

Representative operations:

- `scheduleAlarm(...)`
- `cancelAlarm(int id)`
- `cancelAllAlarms()`
- `getScheduledAlarms()` or `getAlarmState(int id)`
- `getCapabilities()` or `getPermissionState()`
- event delivery for alarm lifecycle changes

This keeps the public contract honest while still allowing rich internal behavior.

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

## Pigeon Boundary Rule

Use:

- `@HostApi` for Flutter to native requests such as schedule, cancel, stop, snooze, or capability queries
- `@FlutterApi` for native to Flutter callbacks such as alarm fired, stopped, snoozed, wake-check expired, or failure events

Pigeon files should stay self-contained and local to each implementation package.

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
- add capability and permission-state reporting
- implement Android scheduling end to end
- provide explicit unsupported or reduced behavior on iOS and macOS
- wire native-to-Dart lifecycle events through `@FlutterApi`

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
