# Warm Alarm Phase 1A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the template `getPlatformName()` API with the first real `warm_alarm` Phase 1A surface: hand-written public alarm models, platform inspection APIs, schedule/cancel stubs, and live event-stream scaffolding across Android, iOS, and macOS.

**Architecture:** Keep the public Dart contract hand-written in `warm_alarm_platform_interface`, re-export it from `warm_alarm`, and keep Pigeon-generated transport types private inside each platform implementation package. Phase 1A stops at API replacement and honest stub behavior: no real alarm scheduling, playback, or wake-check runtime yet.

**Tech Stack:** Dart 3.11, Flutter federated plugin packages, Pigeon, flutter_test, mocktail, melos.

---

## File Map

### Public interface and models

- Modify: `warm_alarm_platform_interface/lib/warm_alarm_platform_interface.dart`
- Modify: `warm_alarm_platform_interface/lib/src/method_channel_warm_alarm.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_audio.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_capabilities.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_event.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_notification.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_permission_state.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_readiness.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_schedule.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_schedule_result.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_snapshot.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_support.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/models.dart`

### Front-facing package

- Modify: `warm_alarm/lib/warm_alarm.dart`
- Modify: `warm_alarm/test/warm_alarm_test.dart`
- Modify: `warm_alarm/example/lib/main.dart`

### Platform packages and generated transport

- Modify: `warm_alarm_android/pigeons/messages.dart`
- Modify: `warm_alarm_ios/pigeons/messages.dart`
- Modify: `warm_alarm_macos/pigeons/messages.dart`
- Modify: `warm_alarm_android/lib/warm_alarm_android.dart`
- Modify: `warm_alarm_ios/lib/warm_alarm_ios.dart`
- Modify: `warm_alarm_macos/lib/warm_alarm_macos.dart`
- Modify: `warm_alarm_android/test/warm_alarm_android_test.dart`
- Modify: `warm_alarm_ios/test/warm_alarm_ios_test.dart`
- Modify: `warm_alarm_macos/test/warm_alarm_macos_test.dart`

### Platform-interface tests

- Modify: `warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`
- Modify: `warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart`

---

### Task 1: Replace the template platform interface with hand-written alarm models

**Files:**

- Create: `warm_alarm_platform_interface/lib/src/models/models.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_support.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_audio.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_notification.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_schedule.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_capabilities.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_permission_state.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_readiness.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_schedule_result.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_snapshot.dart`
- Create: `warm_alarm_platform_interface/lib/src/models/warm_alarm_event.dart`
- Modify: `warm_alarm_platform_interface/lib/warm_alarm_platform_interface.dart`
- Test: `warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`

- [ ] **Step 1: Write the failing platform-interface tests**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarmMock extends WarmAlarmPlatform {
  final _events = StreamController<WarmAlarmEvent>.broadcast();

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async =>
      const WarmAlarmCapabilities(
        exactScheduling: WarmAlarmSupportStatus.supported,
        notificationScheduling: WarmAlarmSupportStatus.supported,
        backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
        fullScreenPresentation: WarmAlarmSupportStatus.unsupported,
        wakeCheck: WarmAlarmSupportStatus.unsupported,
        liveActivity: WarmAlarmSupportStatus.unsupported,
      );

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async =>
      const WarmAlarmPermissionState(
        notificationsGranted: true,
        exactAlarmGranted: false,
        fullScreenIntentGranted: false,
      );

  @override
  Future<WarmAlarmReadiness> getReadiness() async =>
      const WarmAlarmReadiness(
        level: WarmAlarmReadinessLevel.limited,
        reasons: <WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.exactAlarmPermissionDenied,
        ],
      );

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) async =>
      const WarmAlarmScheduleResult(
        alarmId: 7,
        readiness: WarmAlarmReadiness(
          level: WarmAlarmReadinessLevel.limited,
          reasons: <WarmAlarmReadinessReason>[
            WarmAlarmReadinessReason.backgroundExecutionLimited,
          ],
        ),
      );

  @override
  Future<void> cancelAlarm(int id) async {}

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async => const <WarmAlarmSnapshot>[];

  @override
  Stream<WarmAlarmEvent> get events => _events.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WarmAlarmPlatform exposes typed scheduling APIs', () async {
    final platform = WarmAlarmMock();
    WarmAlarmPlatform.instance = platform;

    expect(await WarmAlarmPlatform.instance.getCapabilities(), isA<WarmAlarmCapabilities>());
    expect(await WarmAlarmPlatform.instance.getPermissionState(), isA<WarmAlarmPermissionState>());
    expect(await WarmAlarmPlatform.instance.getReadiness(), isA<WarmAlarmReadiness>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`

Expected: FAIL with missing `WarmAlarmCapabilities`, `WarmAlarmPermissionState`, `WarmAlarmReadiness`, `WarmAlarmScheduleResult`, `WarmAlarmSnapshot`, and new `WarmAlarmPlatform` methods.

- [ ] **Step 3: Add the public model files and interface**

```dart
// warm_alarm_platform_interface/lib/src/models/warm_alarm_support.dart
enum WarmAlarmSupportStatus {
  supported,
  limited,
  unsupported,
  unknown,
}

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

```dart
// warm_alarm_platform_interface/lib/src/models/warm_alarm_readiness.dart
final class WarmAlarmReadiness {
  const WarmAlarmReadiness({
    required this.level,
    required this.reasons,
  });

  final WarmAlarmReadinessLevel level;
  final List<WarmAlarmReadinessReason> reasons;
}

enum WarmAlarmReadinessLevel {
  ready,
  limited,
  blocked,
  unsupported,
}

enum WarmAlarmReadinessReason {
  notificationPermissionDenied,
  exactAlarmPermissionDenied,
  fullScreenPermissionDenied,
  backgroundExecutionLimited,
  backgroundAudioLimited,
  platformUnsupported,
  batteryOptimizationMayDelay,
  unknown,
}
```

```dart
// warm_alarm_platform_interface/lib/warm_alarm_platform_interface.dart
abstract class WarmAlarmPlatform extends PlatformInterface {
  WarmAlarmPlatform() : super(token: _token);

  static final Object _token = Object();
  static WarmAlarmPlatform _instance = MethodChannelWarmAlarm();

  static WarmAlarmPlatform get instance => _instance;

  static set instance(WarmAlarmPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<WarmAlarmCapabilities> getCapabilities();

  Future<WarmAlarmPermissionState> getPermissionState();

  Future<WarmAlarmReadiness> getReadiness();

  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule);

  Future<void> cancelAlarm(int id);

  Future<void> cancelAllAlarms();

  Future<List<WarmAlarmSnapshot>> getScheduledAlarms();

  Stream<WarmAlarmEvent> get events;
}
```

- [ ] **Step 4: Run platform-interface tests**

Run: `flutter test warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add warm_alarm_platform_interface/lib warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart
git commit -m "feat: add typed warm alarm platform models"
```

### Task 2: Replace the front-facing package API and example app surface

**Files:**

- Modify: `warm_alarm/lib/warm_alarm.dart`
- Modify: `warm_alarm/test/warm_alarm_test.dart`
- Modify: `warm_alarm/example/lib/main.dart`

- [ ] **Step 1: Write the failing package and example-facing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class MockWarmAlarmPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements WarmAlarmPlatform {}

void main() {
  late MockWarmAlarmPlatform platform;

  setUp(() {
    platform = MockWarmAlarmPlatform();
    WarmAlarmPlatform.instance = platform;
  });

  test('scheduleAlarm forwards to platform and returns typed result', () async {
    final schedule = WarmAlarmSchedule(
      id: 1,
      scheduledAt: DateTime(2026, 4, 27, 7),
      notification: WarmAlarmNotification(title: 'Wake up', body: 'Now'),
      audio: WarmAlarmAudio(filePath: '/tmp/voice.m4a'),
    );

    const result = WarmAlarmScheduleResult(
      alarmId: 1,
      readiness: WarmAlarmReadiness(
        level: WarmAlarmReadinessLevel.ready,
        reasons: <WarmAlarmReadinessReason>[],
      ),
    );

    when(() => platform.scheduleAlarm(schedule)).thenAnswer((_) async => result);

    expect(await WarmAlarm.scheduleAlarm(schedule), result);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test warm_alarm/test/warm_alarm_test.dart`

Expected: FAIL with missing `WarmAlarm.scheduleAlarm`, `WarmAlarmNotification`, `WarmAlarmAudio`, and `WarmAlarmScheduleResult` APIs.

- [ ] **Step 3: Replace `getPlatformName()` with a static facade and update the example**

```dart
// warm_alarm/lib/warm_alarm.dart
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarm {
  static WarmAlarmPlatform get _platform => WarmAlarmPlatform.instance;

  static Future<WarmAlarmCapabilities> getCapabilities() => _platform.getCapabilities();

  static Future<WarmAlarmPermissionState> getPermissionState() => _platform.getPermissionState();

  static Future<WarmAlarmReadiness> getReadiness() => _platform.getReadiness();

  static Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) =>
      _platform.scheduleAlarm(schedule);

  static Future<void> cancelAlarm(int id) => _platform.cancelAlarm(id);

  static Future<void> cancelAllAlarms() => _platform.cancelAllAlarms();

  static Future<List<WarmAlarmSnapshot>> getScheduledAlarms() =>
      _platform.getScheduledAlarms();

  static Stream<WarmAlarmEvent> get events => _platform.events;
}
```

```dart
// warm_alarm/example/lib/main.dart (shape)
final readiness = await WarmAlarm.getReadiness();
final capabilities = await WarmAlarm.getCapabilities();

setState(() {
  _readiness = readiness.level.name;
  _supportsExact = capabilities.exactScheduling.name;
});
```

- [ ] **Step 4: Run package tests and a focused widget smoke test**

Run: `flutter test warm_alarm/test/warm_alarm_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add warm_alarm/lib/warm_alarm.dart warm_alarm/test/warm_alarm_test.dart warm_alarm/example/lib/main.dart
git commit -m "feat: replace template warm alarm facade"
```

### Task 3: Convert the method-channel fallback to the new typed stub contract

**Files:**

- Modify: `warm_alarm_platform_interface/lib/src/method_channel_warm_alarm.dart`
- Modify: `warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart`

- [ ] **Step 1: Write the failing fallback tests**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(MethodChannelWarmAlarm, () {
    late MethodChannelWarmAlarm methodChannelWarmAlarm;
    final log = <MethodCall>[];

    setUp(() {
      methodChannelWarmAlarm = MethodChannelWarmAlarm();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelWarmAlarm.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'getReadiness') {
            return <String, Object?>{
              'level': 'unsupported',
              'reasons': <String>['platformUnsupported'],
            };
          }
          return null;
        },
      );
    });

    test('getReadiness decodes a typed fallback response', () async {
      final readiness = await methodChannelWarmAlarm.getReadiness();
      expect(readiness.level, WarmAlarmReadinessLevel.unsupported);
      expect(log.single.method, 'getReadiness');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart`

Expected: FAIL with missing `getReadiness` and model decoding logic.

- [ ] **Step 3: Implement a temporary typed fallback**

```dart
class MethodChannelWarmAlarm extends WarmAlarmPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('warm_alarm');

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async =>
      const WarmAlarmCapabilities(
        exactScheduling: WarmAlarmSupportStatus.unknown,
        notificationScheduling: WarmAlarmSupportStatus.unknown,
        backgroundAudioPlayback: WarmAlarmSupportStatus.unknown,
        fullScreenPresentation: WarmAlarmSupportStatus.unknown,
        wakeCheck: WarmAlarmSupportStatus.unknown,
        liveActivity: WarmAlarmSupportStatus.unknown,
      );

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async =>
      const WarmAlarmPermissionState(
        notificationsGranted: false,
        exactAlarmGranted: false,
        fullScreenIntentGranted: false,
      );

  @override
  Future<WarmAlarmReadiness> getReadiness() async =>
      const WarmAlarmReadiness(
        level: WarmAlarmReadinessLevel.unsupported,
        reasons: <WarmAlarmReadinessReason>[
          WarmAlarmReadinessReason.platformUnsupported,
        ],
      );

  @override
  Stream<WarmAlarmEvent> get events => const Stream<WarmAlarmEvent>.empty();
}
```

- [ ] **Step 4: Run fallback tests**

Run: `flutter test warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add warm_alarm_platform_interface/lib/src/method_channel_warm_alarm.dart warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart
git commit -m "test: cover typed fallback warm alarm interface"
```

### Task 4: Add Pigeon transport and typed stub implementations for Android, iOS, and macOS

**Files:**

- Modify: `warm_alarm_android/pigeons/messages.dart`
- Modify: `warm_alarm_ios/pigeons/messages.dart`
- Modify: `warm_alarm_macos/pigeons/messages.dart`
- Modify: `warm_alarm_android/lib/warm_alarm_android.dart`
- Modify: `warm_alarm_ios/lib/warm_alarm_ios.dart`
- Modify: `warm_alarm_macos/lib/warm_alarm_macos.dart`
- Modify: `warm_alarm_android/test/warm_alarm_android_test.dart`
- Modify: `warm_alarm_ios/test/warm_alarm_ios_test.dart`
- Modify: `warm_alarm_macos/test/warm_alarm_macos_test.dart`

- [ ] **Step 1: Write the failing Android, iOS, and macOS wrapper tests**

```dart
test('getCapabilities returns typed stub values', () async {
  when(api.getCapabilities).thenAnswer(
    (_) async => const WarmAlarmCapabilitiesWire(
      exactScheduling: WarmAlarmSupportStatusWire.supported,
      notificationScheduling: WarmAlarmSupportStatusWire.supported,
      backgroundAudioPlayback: WarmAlarmSupportStatusWire.limited,
      fullScreenPresentation: WarmAlarmSupportStatusWire.supported,
      wakeCheck: WarmAlarmSupportStatusWire.unsupported,
      liveActivity: WarmAlarmSupportStatusWire.unsupported,
    ),
  );

  final capabilities = await warmAlarm.getCapabilities();

  expect(capabilities.exactScheduling, WarmAlarmSupportStatus.supported);
});
```

- [ ] **Step 2: Run the wrapper tests to verify they fail**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Run: `flutter test warm_alarm_ios/test/warm_alarm_ios_test.dart`

Run: `flutter test warm_alarm_macos/test/warm_alarm_macos_test.dart`

Expected: FAIL with missing wire types and missing wrapper methods.

- [ ] **Step 3: Expand each Pigeon schema and wrapper to typed Phase 1A stubs**

```dart
// warm_alarm_android/pigeons/messages.dart (same shape mirrored in ios/macos)
@HostApi()
abstract class WarmAlarmApi {
  @async
  WarmAlarmCapabilitiesWire getCapabilities();

  @async
  WarmAlarmPermissionStateWire getPermissionState();

  @async
  WarmAlarmReadinessWire getReadiness();

  @async
  WarmAlarmScheduleResultWire scheduleAlarm(WarmAlarmScheduleWire schedule);

  @async
  void cancelAlarm(int id);

  @async
  void cancelAllAlarms();

  @async
  List<WarmAlarmSnapshotWire> getScheduledAlarms();
}

@FlutterApi()
abstract class WarmAlarmEventsApi {
  @async
  void emitEvent(WarmAlarmEventWire event);
}
```

Keep the Phase 1A event contract transport-only: define the event channel and message types now, but do not promise durable history or full runtime event delivery until Phase 1B validation.

```dart
// warm_alarm_android/lib/warm_alarm_android.dart (shape)
@override
Future<WarmAlarmCapabilities> getCapabilities() async =>
    (await api.getCapabilities()).toModel();

@override
Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) async =>
    (await api.scheduleAlarm(schedule.toWire())).toModel();

@override
Stream<WarmAlarmEvent> get events => _events.stream;
```

- [ ] **Step 4: Regenerate Pigeon bindings and run package tests**

Run: `melos run generate`

Expected: Generated Dart/Kotlin/Swift files update without errors.

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Run: `flutter test warm_alarm_ios/test/warm_alarm_ios_test.dart`

Run: `flutter test warm_alarm_macos/test/warm_alarm_macos_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add warm_alarm_android warm_alarm_ios warm_alarm_macos
git commit -m "feat: add phase 1a warm alarm platform stubs"
```

### Task 5: Verify the Phase 1A repo surface end to end

**Files:**

- Modify: `docs/specs/2026-04-26-warm-alarm-plugin-design.md` only if implementation forces a spec correction
- Test: entire repo verification commands

- [ ] **Step 1: Run targeted package tests**

Run: `flutter test warm_alarm/test/warm_alarm_test.dart`

Run: `flutter test warm_alarm_platform_interface/test/warm_alarm_platform_interface_test.dart`

Run: `flutter test warm_alarm_platform_interface/test/src/method_channel_warm_alarm_test.dart`

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Run: `flutter test warm_alarm_ios/test/warm_alarm_ios_test.dart`

Run: `flutter test warm_alarm_macos/test/warm_alarm_macos_test.dart`

Expected: all PASS

- [ ] **Step 2: Run workspace generation, formatting, and full tests**

Run: `melos run generate`

Run: `melos run format`

Run: `melos run test`

Expected: all commands exit 0

- [ ] **Step 3: Smoke-test the example app interface**

Run: `flutter test warm_alarm/test/warm_alarm_test.dart --plain-name "scheduleAlarm forwards to platform and returns typed result"`

Expected: PASS and confirms the front-facing API no longer depends on `getPlatformName()`.

- [ ] **Step 4: Commit the verification-safe Phase 1A batch**

```bash
git add warm_alarm warm_alarm_platform_interface warm_alarm_android warm_alarm_ios warm_alarm_macos docs/specs/2026-04-26-warm-alarm-plugin-design.md
git commit -m "feat: ship warm alarm phase 1a api surface"
```

## Self-Review Notes

- Spec coverage: this plan covers the approved Phase 1A scope only — typed public API replacement, readiness/capability inspection, schedule result semantics, stub platform implementations, and live-only event semantics.
- No placeholders: every task names exact files, exact commands, and representative code shapes.
- Type consistency: `WarmAlarmScheduleResult`, `WarmAlarmReadiness`, `WarmAlarmReadinessReason`, `WarmAlarmSupportStatus`, and `WarmAlarmEvent` are used consistently across interface, facade, and platform-wrapper tasks.

Plan complete and saved to `docs/plans/2026-04-26-warm-alarm-phase-1a-implementation-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
