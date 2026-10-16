# macOS replacement rollback

## Problem

Issue #74: replacing an alarm removes its pending requests and saved schedule before notification registration succeeds.
A registration failure currently deletes the replacement and returns success with a warning, losing the prior alarm.

## Contract

Snapshot the previous stored schedule and actual pending requests for the same alarm before mutation.
Keep the existing save-before-registration order so a near-due new notification has a matching occurrence token.
On registration failure, remove the replacement requests, restore the previous stored value, and attempt every previous pending request before returning a scheduling error.
Preserve exact pending content and triggers, including a snoozed request and weekly recurrence.
If any restoration fails, keep the previous stored intent and return `scheduling-rollback-failed` with both failure causes.
Otherwise return `scheduling-failed`; a first schedule failure leaves no saved alarm or partial request.
Complete once on the main thread and retain the notification mutation queue until rollback and reply finish.
Successful replacement leaves only the new requests for that alarm and emits the scheduled event.
Host notifications and other alarm IDs remain unchanged.

## Limits

The existing UserDefaults store has no throwing write or disk durability acknowledgement; this change preserves that persistence model.
Initialization can recover missing future one-shot, recurring, and active snooze identifiers from the retained previous schedule.
Already delivered partial notifications cannot be recalled by pending-request rollback.
Concurrent delegate snooze/stop handling and cross-process scheduling are outside this queue's existing contract.
Do not change iOS, public models, generated Pigeon bindings, dependencies, or release versions.
This changes native failure behavior and needs no visual approval.

## Acceptance

Native tests must observe failures at the first and a later replacement registration, exact previous data and request restoration, all restoration attempts after an error, first-schedule cleanup, success cleanup, and a queued cancellation waiting through restoration.
Read the saved value through the store and inspect real UNNotificationRequest objects in the injected notification-center boundary.
