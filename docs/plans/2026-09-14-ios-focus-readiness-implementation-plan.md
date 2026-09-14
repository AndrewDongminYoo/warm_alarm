<!-- cspell:words dongminyu Mirae -->

# iOS Focus Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iOS User Notifications alarms time-sensitive and expose granular notification settings without breaking existing platform packages.

**Architecture:** Add one nullable notification-settings value to the public readiness model, then carry it through the iOS-only Pigeon contract and an injected native settings reader. Keep AlarmKit readiness independent from User Notifications settings, and publish the additive packages in dependency order before updating Mirae.

**Tech Stack:** Dart 3.10, Flutter, Pigeon 26.3.4, Swift 6.1, UserNotifications, Melos, XCTest, GitHub Actions, pub.dev

**Spec:** `docs/specs/2026-09-14-ios-focus-readiness-design.md`

## Global Constraints

- Preserve source compatibility by making `WarmAlarmReadiness.notificationSettings` optional with a `null` default.
- Do not add cases to `WarmAlarmReadinessReason`.
- Do not edit Pigeon-generated Dart, Swift, or Kotlin files directly.
- Do not change Android or macOS behavior.
- Do not change AlarmKit scheduling, sound preparation, or observation.
- Do not restore Dart-owned fallback scheduling in Mirae.
- Run Flutter-backed commands sequentially.
- Publish one dependency stage at a time and confirm pub.dev availability before the next stage.
- Every behavioral change follows Red, Green, Refactor.

---

### Task 1: Add the source-compatible public settings model

**Files:**

- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_notification_settings.dart`
- Create: `warm_alarm_platform_interface/test/src/models/warm_alarm_notification_settings_test.dart`
- Modify: `warm_alarm_platform_interface/lib/src/models/warm_alarm_readiness.dart`
- Modify: `warm_alarm_platform_interface/lib/src/models/models.dart`

**Interfaces:**

- Consumes: Existing `WarmAlarmReadiness` constructor and public model barrel.
- Produces: `WarmAlarmNotificationAuthorizationStatus`, `WarmAlarmNotificationSettings`, and nullable `WarmAlarmReadiness.notificationSettings`.

- [ ] **Step 1: Write the failing public-model tests**

Name the production changes that make the tests pass: the new public types, their fields, and the optional readiness constructor field.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

void main() {
  test('WarmAlarmReadiness keeps notification settings optional', () {
    const readiness = WarmAlarmReadiness(
      level: WarmAlarmReadinessLevel.ready,
      reasons: <WarmAlarmReadinessReason>[],
    );

    expect(readiness.notificationSettings, isNull);
  });

  test('WarmAlarmNotificationSettings preserves granular iOS state', () {
    const settings = WarmAlarmNotificationSettings(
      authorizationStatus: WarmAlarmNotificationAuthorizationStatus.provisional,
      alertsEnabled: false,
      soundsEnabled: true,
      timeSensitiveEnabled: false,
    );

    expect(settings.authorizationStatus, WarmAlarmNotificationAuthorizationStatus.provisional);
    expect(settings.alertsEnabled, isFalse);
    expect(settings.soundsEnabled, isTrue);
    expect(settings.timeSensitiveEnabled, isFalse);
  });
}
```

- [ ] **Step 2: Run the focused test and verify Red**

Run:

```bash
cd warm_alarm_platform_interface
flutter test test/src/models/warm_alarm_notification_settings_test.dart
```

Expected: compilation fails because `WarmAlarmNotificationSettings`, `WarmAlarmNotificationAuthorizationStatus`, and `notificationSettings` do not exist.

- [ ] **Step 3: Add the minimal public implementation**

Create the model:

```dart
enum WarmAlarmNotificationAuthorizationStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
  unknown,
}

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

Add `this.notificationSettings` to the existing readiness constructor and add:

```dart
final WarmAlarmNotificationSettings? notificationSettings;
```

Export the new model from `models.dart`.

- [ ] **Step 4: Run the focused test and verify Green**

Run:

```bash
cd warm_alarm_platform_interface
flutter test test/src/models/warm_alarm_notification_settings_test.dart
```

Expected: both tests pass.

- [ ] **Step 5: Run the interface package gates**

Run sequentially:

```bash
dart format --line-length 120 --set-exit-if-changed lib test
flutter analyze
flutter test --coverage --test-randomize-ordering-seed random
```

Expected: formatting is unchanged, analysis reports no issues, and all interface tests pass.

### Task 2: Release the platform-interface stage

**Files:**

- Modify: `warm_alarm_platform_interface/pubspec.yaml`
- Modify: `warm_alarm_platform_interface/CHANGELOG.md`
- Include: `docs/specs/2026-09-14-ios-focus-readiness-design.md`
- Include: `docs/plans/2026-09-14-ios-focus-readiness-implementation-plan.md`

**Interfaces:**

- Consumes: Task 1 public model.
- Produces: Published `warm_alarm_platform_interface 0.1.3` for the iOS stage.

- [ ] **Step 1: Set the additive release version**

Set `version: 0.1.3` and prepend:

```markdown
# 0.1.3

- Expose granular notification authorization and delivery settings through the optional readiness snapshot.
```

- [ ] **Step 2: Verify the release candidate**

Run sequentially from the repository root:

```bash
flutter pub get
melos run format:ci
melos exec --scope=warm_alarm_platform_interface -- flutter analyze
melos exec --scope=warm_alarm_platform_interface -- flutter test --coverage --test-randomize-ordering-seed random
trunk check docs/specs/2026-09-14-ios-focus-readiness-design.md docs/plans/2026-09-14-ios-focus-readiness-implementation-plan.md warm_alarm_platform_interface
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 3: Commit the interface concern**

Stage only the two documents and `warm_alarm_platform_interface` paths after inspecting the index.

```bash
git commit -m "feat(interface): expose notification readiness settings"
```

- [ ] **Step 4: Run PR loop stage 1**

Push `feat/and-148-ios-focus-readiness`, open a PR against `main`, and link AND-148.
Use a five-round and five-hour public-repository budget.
Require current-head CI, Codex, CodeRabbit, and zero unresolved review threads.
Use a merge commit because the specification and interface implementation are coherent, separately useful commits.

- [ ] **Step 5: Publish and verify the interface package**

After the PR is confirmed merged, update local `main`, create the exact tag, and push it:

```bash
git tag warm_alarm_platform_interface-v0.1.3 <verified-main-sha>
git push origin warm_alarm_platform_interface-v0.1.3
```

Wait for the tag workflow and verify that the pub.dev API reports version `0.1.3` before Task 3.

### Task 3: Carry granular settings through the iOS wire mapping

**Files:**

- Modify: `warm_alarm_ios/pigeons/messages.dart`
- Modify: `warm_alarm_ios/lib/warm_alarm_ios.dart`
- Modify: `warm_alarm_ios/test/warm_alarm_ios_test.dart`
- Regenerate: `warm_alarm_ios/lib/src/messages.g.dart`
- Regenerate: `warm_alarm_ios/ios/warm_alarm_ios/Sources/warm_alarm_ios/Messages.g.swift`

**Interfaces:**

- Consumes: `WarmAlarmNotificationSettings` from platform-interface 0.1.3.
- Produces: `WarmAlarmNotificationAuthorizationStatusWire`, `WarmAlarmNotificationSettingsWire`, nullable `WarmAlarmReadinessWire.notificationSettings`, and lossless Dart mapping.

- [ ] **Step 1: Write the failing iOS Dart mapping test**

Add a test that supplies every wire authorization status through `api.getReadiness` and asserts the public model.

```dart
test('getReadiness maps granular notification settings', () async {
  const statuses = <WarmAlarmNotificationAuthorizationStatusWire, WarmAlarmNotificationAuthorizationStatus>{
    WarmAlarmNotificationAuthorizationStatusWire.notDetermined:
        WarmAlarmNotificationAuthorizationStatus.notDetermined,
    WarmAlarmNotificationAuthorizationStatusWire.denied: WarmAlarmNotificationAuthorizationStatus.denied,
    WarmAlarmNotificationAuthorizationStatusWire.authorized: WarmAlarmNotificationAuthorizationStatus.authorized,
    WarmAlarmNotificationAuthorizationStatusWire.provisional: WarmAlarmNotificationAuthorizationStatus.provisional,
    WarmAlarmNotificationAuthorizationStatusWire.ephemeral: WarmAlarmNotificationAuthorizationStatus.ephemeral,
    WarmAlarmNotificationAuthorizationStatusWire.unknown: WarmAlarmNotificationAuthorizationStatus.unknown,
  };

  for (final entry in statuses.entries) {
    when(api.getReadiness).thenAnswer(
      (_) async => WarmAlarmReadinessWire(
        level: WarmAlarmReadinessLevelWire.limited,
        reasons: <WarmAlarmReadinessReasonWire>[WarmAlarmReadinessReasonWire.backgroundExecutionLimited],
        notificationSettings: WarmAlarmNotificationSettingsWire(
          authorizationStatus: entry.key,
          alertsEnabled: false,
          soundsEnabled: true,
          timeSensitiveEnabled: false,
        ),
      ),
    );

    final readiness = await warmAlarm.getReadiness();
    expect(readiness.notificationSettings?.authorizationStatus, entry.value);
    expect(readiness.notificationSettings?.alertsEnabled, isFalse);
    expect(readiness.notificationSettings?.soundsEnabled, isTrue);
    expect(readiness.notificationSettings?.timeSensitiveEnabled, isFalse);
  }
});
```

- [ ] **Step 2: Run the focused test and verify Red**

Run:

```bash
cd warm_alarm_ios
flutter test test/warm_alarm_ios_test.dart
```

Expected: compilation fails because the iOS wire settings types and mapping do not exist.

- [ ] **Step 3: Add the Pigeon input and regenerate outputs**

Add the exact enum and class from the design to `warm_alarm_ios/pigeons/messages.dart`.
Add nullable `WarmAlarmNotificationSettingsWire? notificationSettings` to `WarmAlarmReadinessWire`.
Run from the repository root:

```bash
melos run generate
```

Inspect generated diffs and require changes only in the two iOS Pigeon outputs.

- [ ] **Step 4: Add the Dart wire mapping**

Pass `wire.notificationSettings` through `_readinessFromWire` and map every authorization value with an exhaustive switch.

```dart
WarmAlarmNotificationSettings? _notificationSettingsFromWire(WarmAlarmNotificationSettingsWire? wire) {
  if (wire == null) return null;
  return WarmAlarmNotificationSettings(
    authorizationStatus: _notificationAuthorizationStatusFromWire(wire.authorizationStatus),
    alertsEnabled: wire.alertsEnabled,
    soundsEnabled: wire.soundsEnabled,
    timeSensitiveEnabled: wire.timeSensitiveEnabled,
  );
}
```

- [ ] **Step 5: Run the focused test and verify Green**

Run:

```bash
cd warm_alarm_ios
flutter test test/warm_alarm_ios_test.dart
```

Expected: the iOS Dart suite passes.

### Task 4: Make native User Notifications delivery time-sensitive

**Files:**

- Modify: `warm_alarm_ios/ios/warm_alarm_ios/Sources/warm_alarm_ios/WarmAlarmPlugin.swift`
- Modify: `warm_alarm_ios/ios/warm_alarm_ios/Sources/warm_alarm_ios/WarmAlarmDelegate.swift`
- Modify: `warm_alarm_ios/ios/warm_alarm_ios/Tests/warm_alarm_ios_tests/WarmAlarmRequestRegistrationTests.swift`

**Interfaces:**

- Consumes: Task 3 generated Swift wire types and existing injected `notificationCenter`.
- Produces: `WarmAlarmNotificationSettingsSnapshot`, `NotificationSettingsReader`, time-sensitive request options, time-sensitive alarm content, and backend-aware readiness.

- [ ] **Step 1: Write failing native tests for request options and content**

Add tests that fail when `.timeSensitive` is absent:

```swift
func testSupportedAuthorizationOptionsRequestTimeSensitiveDelivery() {
    XCTAssertTrue(WarmAlarmPlugin.notificationAuthorizationOptions(timeSensitiveAvailable: true).contains(.timeSensitive))
    XCTAssertFalse(WarmAlarmPlugin.notificationAuthorizationOptions(timeSensitiveAvailable: false).contains(.timeSensitive))
}

func testAlarmContentUsesTimeSensitiveInterruptionLevel() throws {
    guard #available(iOS 15.0, *) else { throw XCTSkip("Time Sensitive Notifications require iOS 15") }
    let delegate = makeWarmAlarmDelegate(label: "time_sensitive_content")
    let content = delegate.makeContent(from: WarmAlarmScheduleData.from(
        wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000),
        fallbackAnchorMillis: 1_900_000_000_000
    ))
    XCTAssertEqual(content.interruptionLevel, .timeSensitive)
}
```

- [ ] **Step 2: Run the native test target and verify Red**

Check machine load first, select one available iPhone simulator, and run the `RunnerTests` target through the example workspace.

```bash
uptime
simulator_udid=$(xcrun simctl list devices available --json | jq -r '[.devices[][] | select(.name | startswith("iPhone"))] | last | .udid')
result_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/warm-alarm-runner-tests.XXXXXX")
cd warm_alarm/example/ios
xcodebuild test -quiet -workspace Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$simulator_udid" -only-testing:RunnerTests -resultBundlePath "$result_directory/RunnerTests.xcresult"
```

Expected: compilation fails because `notificationAuthorizationOptions` does not exist, or the content assertion fails because interruption level is not time-sensitive.

- [ ] **Step 3: Add the minimal request and content behavior**

Add:

```swift
static func notificationAuthorizationOptions(timeSensitiveAvailable: Bool) -> UNAuthorizationOptions {
    var options: UNAuthorizationOptions = [.alert, .sound]
    if timeSensitiveAvailable { options.insert(.timeSensitive) }
    return options
}
```

Use `#available(iOS 15.0, *)` to select the Boolean in `requestNotificationPermission`.
Use the injected `notificationCenter` for the request.
Set `content.interruptionLevel = .timeSensitive` in `WarmAlarmDelegate.makeContent` under the same availability guard.

- [ ] **Step 4: Run the native target and verify Green for delivery behavior**

Run the same `RunnerTests` command.

Expected: every native test passes with no skip on the selected supported simulator.

- [ ] **Step 5: Write failing native tests for the injected settings matrix**

Name the production changes that make these tests pass: `NotificationSettingsReader`, `WarmAlarmNotificationSettingsSnapshot`, and propagation through `getReadiness`.
Cover authorized, provisional, denied, not-determined, alert-disabled, sound-disabled, and time-sensitive-disabled values.
For each case, call `plugin.getReadiness`, then assert `notificationSettings` and the readiness table from the spec.
Also assert that an authorized AlarmKit backend stays `ready` when every notification setting is disabled.

```swift
func testInjectedProvisionalSettingsRemainVisibleInReadiness() throws {
    let injected = WarmAlarmNotificationSettingsSnapshot(
        authorizationStatus: .provisional,
        alertsEnabled: false,
        soundsEnabled: true,
        timeSensitiveEnabled: false
    )
    let plugin = makeSoundLifecyclePlugin(
        backend: RecordingAlarmKitBackend(scheduleError: nil, authorizationState: .denied),
        notificationSettingsReader: { completion in completion(injected) }
    )
    let completed = expectation(description: "readiness returns injected notification settings")

    plugin.getReadiness { result in
        let readiness = try? result.get()
        XCTAssertEqual(readiness?.level, .limited)
        XCTAssertEqual(readiness?.notificationSettings?.authorizationStatus, .provisional)
        XCTAssertEqual(readiness?.notificationSettings?.alertsEnabled, false)
        XCTAssertEqual(readiness?.notificationSettings?.soundsEnabled, true)
        XCTAssertEqual(readiness?.notificationSettings?.timeSensitiveEnabled, false)
        completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    withExtendedLifetime(plugin) {}
}
```

- [ ] **Step 6: Run the native target and verify Red**

Run the same `RunnerTests` command.

Expected: compilation fails because the injected reader and native settings snapshot do not exist.

- [ ] **Step 7: Implement the settings reader and readiness mapping**

Add an initializer dependency with a system-backed default:

```swift
typealias NotificationSettingsReader = (@escaping (WarmAlarmNotificationSettingsSnapshot) -> Void) -> Void
```

Convert every `UNAuthorizationStatus` to the matching wire status.
Convert alert and sound to enabled Booleans.
Convert `timeSensitiveSetting` on iOS 15 and later, and use `nil` before iOS 15.

Change `captureNotificationSnapshot` to call the injected reader.
Change `permissionSnapshot` to accept the value snapshot, compute `notificationsGranted`, attach `WarmAlarmNotificationSettingsWire`, and preserve the backend rules from the spec.

- [ ] **Step 8: Run the native target and verify Green for the settings matrix**

Run the same `RunnerTests` command.

Expected: every native test passes and the new matrix assertions observe the injected values.

- [ ] **Step 9: Run the iOS package gates**

Run sequentially:

```bash
melos run format:ci
melos exec --scope=warm_alarm_ios -- flutter analyze
melos exec --scope=warm_alarm_ios -- flutter test --coverage --test-randomize-ordering-seed random
trunk check warm_alarm_ios
git diff --check
```

Run the native `RunnerTests` target once more after formatting.
Expected: every command exits zero and the native result contains a positive test count.

### Task 5: Release the iOS implementation stage

**Files:**

- Modify: `warm_alarm_ios/pubspec.yaml`
- Modify: `warm_alarm_ios/CHANGELOG.md`
- Modify: `warm_alarm_ios/README.md`

**Interfaces:**

- Consumes: Published platform-interface 0.1.3 and Tasks 3-4 implementation.
- Produces: Published `warm_alarm_ios 0.1.8`.

- [ ] **Step 1: Set package constraints and documentation**

Set `version: 0.1.8` and `warm_alarm_platform_interface: ^0.1.3`.
Prepend a changelog entry for time-sensitive delivery and granular readiness.
Document the host interpretation of authorization, alert, sound, and time-sensitive settings.

- [ ] **Step 2: Verify the iOS release candidate**

Run `flutter pub get`, the Task 4 iOS gates, the native test target, and `git diff --check` sequentially.

- [ ] **Step 3: Commit the iOS concern**

Stage only `warm_alarm_ios` paths and inspect the complete index.

```bash
git commit -m "feat(ios): align Focus delivery and readiness"
```

- [ ] **Step 4: Run PR loop stage 2**

Create a fresh branch from updated `main`, push it, open the iOS PR, and complete the current-head CI and hosted-review gates.
Use a merge commit because the generated contract and native behavior form one coherent package release.

- [ ] **Step 5: Publish and verify the iOS package**

Tag the verified merge SHA and push:

```bash
git tag warm_alarm_ios-v0.1.8 <verified-main-sha>
git push origin warm_alarm_ios-v0.1.8
```

Verify the tag workflow and pub.dev version `0.1.8` before Task 6.

### Task 6: Raise the facade minimums and document the host contract

**Files:**

- Modify: `warm_alarm/pubspec.yaml`
- Modify: `warm_alarm/CHANGELOG.md`
- Modify: `warm_alarm/README.md`
- Modify: `warm_alarm/test/warm_alarm_test.dart`

**Interfaces:**

- Consumes: Published platform-interface 0.1.3 and iOS 0.1.8.
- Produces: `warm_alarm 0.1.4` with minimum dependency versions that contain the new contract.

- [ ] **Step 1: Add the facade regression test**

Extend the existing `getReadiness delegates to platform` test so its platform result contains `WarmAlarmNotificationSettings` and assert that `WarmAlarm.getReadiness` returns the same value.

- [ ] **Step 2: Run the focused facade test before changing constraints**

Run:

```bash
cd warm_alarm
flutter test test/warm_alarm_test.dart
```

Expected: the test passes because the facade delegates the public object without copying it.
This is a compatibility regression test, not a behavioral Red step; the behavioral Red cycles are owned by Tasks 1, 3, and 4.

- [ ] **Step 3: Set the facade release constraints**

Set `version: 0.1.4`, `warm_alarm_ios: ^0.1.8`, and `warm_alarm_platform_interface: ^0.1.3`.
Prepend the changelog entry and document `notificationSettings` with host guidance in the README.

- [ ] **Step 4: Verify the facade release candidate**

Run sequentially:

```bash
flutter pub get
melos run format:ci
melos exec --scope=warm_alarm -- flutter analyze
melos exec --scope=warm_alarm -- flutter test --coverage --test-randomize-ordering-seed random
trunk check warm_alarm
git diff --check
```

Expected: every command exits zero.

- [ ] **Step 5: Commit and complete PR loop stage 3**

Stage only `warm_alarm` paths and inspect the complete index.

```bash
git commit -m "feat(facade): expose iOS notification readiness"
```

Create a fresh branch from updated `main`, push it, open the facade PR, and complete current-head CI and hosted-review gates.
Use a merge commit for the package release commit.

- [ ] **Step 6: Publish and verify the facade package**

Tag the verified merge SHA and push:

```bash
git tag warm_alarm-v0.1.4 <verified-main-sha>
git push origin warm_alarm-v0.1.4
```

Verify the tag workflow and pub.dev version `0.1.4` before Task 7.

### Task 7: Update Mirae to the hosted contract

**Files:**

- Modify: `/Users/dongminyu/Development/01_personal/mirae/pubspec.yaml`
- Modify: `/Users/dongminyu/Development/01_personal/mirae/pubspec.lock`
- Modify only if required by generated dependency state: `/Users/dongminyu/Development/01_personal/mirae/ios/Podfile.lock`

**Interfaces:**

- Consumes: Published `warm_alarm 0.1.4` and its endorsed iOS package.
- Produces: Mirae resolution against `warm_alarm 0.1.4`, `warm_alarm_ios 0.1.8`, and `warm_alarm_platform_interface 0.1.3`.

- [ ] **Step 1: Create a Mirae branch from verified clean `main`**

Fetch `origin`, require `HEAD == origin/main`, verify no staged, unstaged, untracked, or ignored deliverable exists, then create `feat/and-148-ios-focus-readiness` in the main Mirae workspace.

- [ ] **Step 2: Raise and resolve the hosted dependency**

Set `warm_alarm: ^0.1.4` and run:

```bash
flutter pub get
flutter pub upgrade warm_alarm
```

Inspect `pubspec.lock` and require the three exact published versions from the task interface.

- [ ] **Step 3: Run Mirae verification**

Check machine load, then run sequentially:

```bash
merry format
flutter analyze
merry test
```

Expected: formatting completes, analysis reports no issues, and the full test suite passes.

- [ ] **Step 4: Commit and run the Mirae PR loop**

Stage only the dependency manifest and regenerated lockfiles.

```bash
git commit -m "build(deps): adopt granular iOS alarm readiness"
```

Push, open the Mirae PR against `main`, and complete current-head CI and hosted-review gates.
Use a merge commit for the dependency adoption commit.

### Task 8: Complete physical Focus acceptance

**Files:**

- Modify after observation: `/Users/dongminyu/Development/01_personal/mirae/docs/notes/2026-07-22-alarm-device-matrix.md`

**Interfaces:**

- Consumes: The merged Mirae hosted-package build and the registered iPhone 16 Pro.
- Produces: A direct Focus observation linked from AND-50 and AND-148.

- [ ] **Step 1: Build the declared development-flavor release artifact**

Check machine load and build the development flavor from the Mirae repository root:

```bash
uptime
flutter build ios --release --flavor development --no-pub
```

Do not use `flutter build` as a generic verification gate; this build exists only for the approved physical-device acceptance.

- [ ] **Step 2: Announce and install the artifact**

Immediately before the device write, state the exact artifact, bundle identifier, and that the existing daily-phone app will be overwritten without deletion.
Use an install-over-existing command rather than `flutter install`.

```bash
xcrun devicectl device install app --device 00008140-001938282206801C build/ios/iphoneos/Runner.app
```

- [ ] **Step 3: Announce and launch the app**

Immediately before launch, state whether the command terminates an existing process.
Launch without `--terminate-existing` unless the scenario explicitly requires it.

```bash
xcrun devicectl device process launch --device 00008140-001938282206801C kr.mirae.app.dev
```

- [ ] **Step 4: Run the operator-observed Focus scenario**

Enable Focus, schedule a User Notifications fallback scenario where supported, and record the authorization, alerts, sounds, and Time Sensitive Notifications settings.
Observe scheduled time, first audible time, lifecycle state, Stop, and Snooze.
Automation does not infer audibility.

- [ ] **Step 5: Record and publish the evidence**

Add the exact device, OS, app version, build, SHA, settings, timing, and operator observation to the device matrix.
Update AND-50 and AND-148 with the result.
Mark AND-148 complete only if every acceptance criterion is satisfied.

## Final Verification

- [ ] Confirm `warm_alarm_platform_interface 0.1.3`, `warm_alarm_ios 0.1.8`, and `warm_alarm 0.1.4` are visible on pub.dev.
- [ ] Confirm both repositories' merged PR head and merge SHAs.
- [ ] Confirm all applicable checks refer to the final pushed heads.
- [ ] Confirm zero unresolved review threads for every PR.
- [ ] Confirm Mirae `main` resolves the exact hosted package versions.
- [ ] Confirm the physical Focus result is recorded without inferring sound from automation.
- [ ] Report the build left installed on the daily iPhone.
