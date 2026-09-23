# Wake-check warning contract

## Problem

`WarmAlarmSchedule.wakeCheck` is supported on Android but ignored by the iOS and macOS schedule wire mappings.
The Apple implementations report wake-check as unsupported through capabilities, yet a caller that schedules without inspecting capabilities receives no warning about the ignored option.

## Scope

Add an optional `WarmAlarmWarning.code` value named `unsupportedWakeCheck` to the public platform interface.
When iOS or macOS receives a schedule with `wakeCheck`, return that code and a readable message while preserving any native scheduling warning in the message.
Leave the existing warning unchanged when `wakeCheck` is absent.
Document the result on the app-facing package.

## Constraints

Keep the warning model backward compatible by making the code nullable.
Do not change the Pigeon schema or native scheduling behavior because wake-check is unsupported on both Apple platforms.
Publish the interface before any platform package that references the new enum, then publish the app-facing package after its platform dependencies are available on pub.dev.

## Acceptance

The Apple mapping tests must fail on the ignored wake-check behavior before the implementation and pass afterward.
Package tests, Flutter analysis, scoped Dart formatting, and Trunk checks must pass.
Each release PR must pass its hosted package workflow, including Pana against already published dependency versions.
