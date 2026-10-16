# macOS host notification delegate

## Problem

Issue #75: plugin registration replaces the shared notification center delegate and drops callbacks for host notifications.

## Contract

Install a retained forwarding delegate during plugin registration.
Route `WARM_ALARM` content exclusively to the alarm delegate and other content to the previous host delegate.
Preserve the host's presentation options and asynchronous completion timing without adding a second completion.
When no host or optional callback exists, complete presentation with no options and complete responses immediately.
Forward notification settings callbacks, including a nil notification, to the host.
Keep the host reference weak, flatten repeated plugin registrations, and restore the newest live previous delegate on release only if this plugin still owns the center's delegate slot.

## Scope and limits

Use the iOS delegate ownership pattern without its iOS-only Flutter lifecycle protocol.
Do not change scheduling, audio, public APIs, Pigeon outputs, package versions, or notification category registration.
Another plugin that replaces the shared delegate later must implement its own forwarding.
The plugin does not repair a host callback that itself omits or repeats completion.
No visual approval is needed for this native routing correction.

## Acceptance

Register against a real notification center with a fake host installed first, then invoke the installed delegate's foreground, response, and settings callbacks.
Verify host delivery and completion counts, owned notification isolation, optional-method fallback, weak ownership, repeated registration, restoration order, and external replacement preservation.
Use a small app-bundle XCTest host because the system notification center requires an application bundle; bare SwiftPM XCTest cannot supply one.
Notification and response fixtures must assert decoded content and action identifiers before delivery.
These tests exercise registration and callback dispatch, not operating-system notification delivery or user interaction.
