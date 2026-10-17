# Scheduling warnings list

**Date:** 2026-10-17
**Decision owner:** operator
**Issues:** [#115](https://github.com/AndrewDongminYoo/warm_alarm/issues/115) (decision), [#122](https://github.com/AndrewDongminYoo/warm_alarm/issues/122) (implementation)

## Problem

`WarmAlarmScheduleResult.warning` holds one optional `WarmAlarmWarning`.
When a request contains more than one option that a platform does not apply, the result can report only one of them.
For example, an iOS or macOS request with a wake-check reports `unsupportedWakeCheck` and folds any native warning text into the same message.
A null warning also does not guarantee that every platform-specific option was applied.

## Decision

Add a list of warnings to the scheduling result and keep the existing single field.
The operator selected this option over two others on 2026-10-17:

- Keep the single field and document the limit.
- Add a strict mode that fails scheduling when any option is unsupported.

## Required behavior

- `WarmAlarmScheduleResult` gains `warnings`, a list of `WarmAlarmWarning` that is empty when the platform reports no warning.
- `warning` stays in the model and equals the first entry of `warnings`, or null when the list is empty.
- Each platform package reports every warning that applies to the request as a separate entry, in the order the platform detects them.
- On iOS and macOS, the wake-check warning and a native warning become two entries instead of one combined message.
- Existing `WarmAlarmWarningCode` values keep their meaning. A warning without a classified code keeps a null code.

## Constraints

- The change is additive: existing callers that read only `warning` keep working without code changes.
- A Pigeon schema change is regenerated with `melos run generate` and never hand-edited.
- Release follows the interface-first order: `warm_alarm_platform_interface`, then the three platform packages with the raised interface floor, then the `warm_alarm` facade.
- Tests cover zero, one, and several warnings in each platform's Dart mapping and in the facade.
