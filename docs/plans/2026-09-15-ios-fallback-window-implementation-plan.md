<!-- cspell:words dongminyu Mirae xcresulttool -->

# iOS Fallback Window Implementation Plan

**Goal:** Extend the iOS User Notifications fallback horizon from T+3 minutes to T+5 minutes, publish the scoped iOS package, and refresh Mirae's hosted resolution with evidence at each boundary.

**Architecture:** Keep the existing primary-plus-fallback request model and increase the shared iOS fallback count from six to ten.
Reuse the current capacity, recovery, rollback, and cancellation paths so every path derives the longer identifier range from one policy constant.

**Tech Stack:** Swift 6.1, XCTest, UserNotifications, Dart 3.10, Flutter, Melos, Trunk, pub.dev

**Spec:** `docs/specs/2026-09-15-ios-fallback-window-design.md`

## Global Constraints

- Obtain operator approval for the spec before changing Swift or package metadata.
- Follow Red, Green, Refactor.
- Do not introduce a repeating-notification abstraction or change AlarmKit.
- Do not edit generated Pigeon or Flutter files.
- Keep Flutter-backed commands sequential.
- Keep structural and behavioral changes in separate commits if a structural change becomes necessary.
- Do not push, publish, update Linear, or write to a physical device without the required explicit approval at that boundary.
- Do not mark AND-170 or AND-50 complete without the physical User Notifications evidence defined by the spec.

### Task 1: Prove and implement the ten-fallback policy

**Files:**

- Modify: `warm_alarm_ios/ios/warm_alarm_ios/Tests/warm_alarm_ios_tests/WarmAlarmRequestRegistrationTests.swift`
- Modify: `warm_alarm_ios/ios/warm_alarm_ios/Sources/warm_alarm_ios/WarmAlarmPlugin.swift`

**Produces:** One primary request at T and ten fallback requests through T+5 minutes on every User Notifications construction path.

- [x] **Step 1: Add one explicit failing policy test**

Add `testFallbackPolicySchedulesTenFollowUpsThroughFiveMinutes` to `WarmAlarmRequestTests`.
Assert that `makeRequests` returns eleven requests, fallback identifiers `#fallback#1` through `#fallback#10`, and a last trigger at `anchor + 300_000` milliseconds.
Do not derive the expected count or final time from production constants.

- [x] **Step 2: Run the focused XCTest and verify Red**

Select one available iPhone Simulator UDID, then run from `warm_alarm/example/ios`:

```bash
simulator_udid=$(xcrun simctl list devices available --json | jq -r '[.devices[][] | select(.name | startswith("iPhone"))] | last | .udid')
xcodebuild test -quiet -workspace Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$simulator_udid" -only-testing:RunnerTests/WarmAlarmRequestTests/testFallbackPolicySchedulesTenFollowUpsThroughFiveMinutes IPHONEOS_DEPLOYMENT_TARGET=15.0
```

Expected: the test fails because the current implementation returns six fallbacks and ends at T+3 minutes.
The command-line deployment target lets Xcode 27 run the test host without changing the package's iOS 13 deployment contract.

- [x] **Step 3: Apply the minimal production change**

Change `WarmAlarmPlugin.fallbackCount` from `6` to `10` and let the occurrence-metadata ordinal validator reference the same constant.
Do not add a new policy type or modify the 30-second interval.

- [x] **Step 4: Update existing contract assertions**

Update only the tests whose explicit six-fallback expectations describe the old policy.
Cover one-shot construction, recurring construction, snooze construction, occurrence ordinals, capacity selection, recovery, rollback, cancellation identifiers, and delivered-notification cleanup.
Keep partial-capacity expectations based on the actual available slots so the tests continue to prove prefix selection rather than only the new maximum.

- [x] **Step 5: Run focused tests and verify Green**

Run the new policy test and the affected `WarmAlarmRequestTests` suite through the `RunnerTests` host.
Expected: every selected test passes, the full chain ends at T+5 minutes, and constrained-capacity cases still preserve core requests.

### Task 2: Verify the iOS behavior and prepare release metadata

**Files:**

- Modify: `warm_alarm_ios/README.md`
- Modify: `warm_alarm_ios/pubspec.yaml`
- Modify: `warm_alarm_ios/CHANGELOG.md`
- Include: `docs/specs/2026-09-15-ios-fallback-window-design.md`
- Include: `docs/plans/2026-09-15-ios-fallback-window-implementation-plan.md`

**Produces:** A documented and testable `warm_alarm_ios 0.1.9` release candidate.

- [x] **Step 1: Run every hosted native iOS test**

Run from `warm_alarm/example/ios` with the selected Simulator UDID:

```bash
result_directory=$(mktemp -d)
xcodebuild test -quiet -workspace Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$simulator_udid" -only-testing:RunnerTests -resultBundlePath "$result_directory/RunnerTests.xcresult" IPHONEOS_DEPLOYMENT_TARGET=15.0
xcrun xcresulttool get test-results summary --path "$result_directory/RunnerTests.xcresult" --format json | jq -er '.totalTestCount | select(. > 0)'
```

Expected: `xcodebuild` exits zero and the result bundle reports a positive test count.

- [x] **Step 2: Update package documentation and version**

Change the README statement from six fallback slots to ten.
Set `warm_alarm_ios` to version `0.1.9` and add a changelog entry that states the exact T+5-minute User Notifications behavior.
If the current package version is no longer `0.1.8`, stop and recalculate the next version before editing release metadata.

- [x] **Step 3: Run repository gates sequentially**

Run from the repository root:

```bash
flutter pub get
melos run format
melos run test
melos run format:ci
trunk check
git diff --check
```

Expected: every command exits zero.
Inspect the diff after `melos run format` and revert no author-unknown work.
Confirm that generated Pigeon and Flutter files have no diff.

- [x] **Step 4: Prepare the behavioral commit**

Stage only the two design documents and the scoped `warm_alarm_ios` paths.
Inspect the complete index before committing.
Use:

```bash
git commit -m "fix(ios): extend fallback notification window"
```

### Task 3: Deliver and publish `warm_alarm_ios`

**Consumes:** The verified Task 2 commit.

**Produces:** A merged exact-head change and published `warm_alarm_ios 0.1.9` package.

- [ ] **Step 1: Request approval for external delivery**

Present the commit SHA, clean worktree status, local gate results, proposed branch, PR title, and package tag.
Wait for explicit approval before pushing or publishing.

- [ ] **Step 2: Run the repository PR workflow**

Push a scoped branch, open a PR against `main`, and link AND-170.
Require current-head CI and resolve only findings that the current diff actually fixes.
Leave merge to the operator.

- [ ] **Step 3: Verify the merged source before tagging**

After the operator confirms or performs the merge, fetch the remote and verify the exact merged head, package version, changelog, and clean local `main`.
Do not infer merge state from a gone-upstream branch.

- [ ] **Step 4: Request approval and publish the package**

After explicit tag-push approval, tag the verified merge commit and push the tag:

```bash
git tag warm_alarm_ios-v0.1.9 <verified-main-sha>
git push origin warm_alarm_ios-v0.1.9
```

Wait for the tag workflow and verify that the pub.dev API reports `warm_alarm_ios 0.1.9` before changing Mirae.

### Task 4: Refresh Mirae's hosted iOS implementation

**Repository:** `/Users/dongminyu/Development/01_personal/mirae`

**Files:**

- Modify: `pubspec.lock`
- Verify without changing unless required by resolution: `pubspec.yaml`

**Produces:** Mirae resolves the published `warm_alarm_ios 0.1.9` through its existing `warm_alarm` dependency.

- [ ] **Step 1: Reverify Mirae before editing**

Fetch `origin` and verify the absolute repository root, personal remote, current `main`, worktree list, staged state, unstaged state, and untracked state.
Preserve every author-unknown change.

- [ ] **Step 2: Upgrade the hosted dependency resolution**

Run sequentially from the Mirae root:

```bash
flutter pub upgrade warm_alarm
flutter pub get
```

Require `pubspec.lock` to resolve `warm_alarm_ios 0.1.9` from `https://pub.dev`.
Keep `warm_alarm: ^0.1.4` unchanged because the published facade already permits the compatible iOS package.
If the solver does not select `0.1.9`, stop and diagnose the hosted constraints instead of adding a direct platform-package dependency.

- [ ] **Step 3: Run Mirae gates sequentially**

Run:

```bash
merry format
flutter analyze
merry test
```

Expected: every command exits zero.
Inspect the manifest and lockfile after `merry format` because that command can apply Dart fixes outside the intended dependency-only scope.

- [ ] **Step 4: Commit and deliver the lockfile update**

Stage the explicit dependency files and inspect the index.
Use:

```bash
git commit -m "fix(ios): adopt extended fallback window"
```

Request separate approval before pushing the Mirae branch or opening its PR.
Leave merge to the operator.

### Task 5: Verify the physical User Notifications window

**Produces:** Device evidence for AND-170 and an honest remaining status for AND-50.

- [ ] **Step 1: Select a valid device path**

Use a physical iPhone that can demonstrably select the User Notifications backend.
Record the device model, iOS version, app commit, resolved `warm_alarm_ios` version, effective backend, scheduled T, and pending-request capacity warning state.
An AlarmKit-owned run does not satisfy this task.

- [ ] **Step 2: Request each daily-phone write separately**

Before each install, launch, or terminate-existing action on the iPhone 16 Pro, state the exact artifact, bundle identifier, action, and expected effect on the installed app.
One approval does not authorize the next device write.

- [ ] **Step 3: Observe the complete window**

Schedule an occurrence with enough pending capacity for the full chain.
Do not respond before T+5 minutes.
Record each audible or visible delivery time and confirm the final fallback occurs at T+5 minutes.

- [ ] **Step 4: Verify teardown**

Schedule another full chain, invoke Stop before the last fallback, and inspect the remaining pending requests through a concrete reader.
Confirm that no request for the stopped occurrence remains through `#fallback#10`.

- [ ] **Step 5: Reconcile issue state**

If automated, publication, Mirae, and device evidence all pass, present the evidence and request approval before changing Linear.
If compatible hardware or a User Notifications path is unavailable, report device acceptance as `[PARTIAL]` and keep AND-170 and AND-50 open.
