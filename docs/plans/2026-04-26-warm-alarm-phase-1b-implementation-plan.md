# Warm Alarm Phase 1B Android Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Turn the current Android runtime path in `warm_alarm_android` into a verified one-shot alarm proof: schedule an alarm, fire it while backgrounded, play audio, and deliver stop/snooze lifecycle events back to Dart.

**Architecture:** Keep the public Dart API unchanged from Phase 1A and deepen only the Android implementation. Phase 1B should improve Android runtime correctness and proof, not broaden public API scope or introduce wake-check/retrigger behavior from Phase 2.

**Tech Stack:** Flutter federated plugin, Dart 3.11, Pigeon, Kotlin Android AlarmManager + BroadcastReceiver + foreground service, flutter_test, mocktail.

**Phase 1B Definition of Done:**

- Android schedules real one-shot alarms through `AlarmManager`.
- Android can fire an alarm while the app is backgrounded.
- Android plays local-file audio or falls back cleanly.
- Stop and snooze actions emit Dart events.
- Permission-denied or unavailable cases surface as explicit blocked/limited readiness or failure signals.
- Android-specific tests cover schedule/cancel/event mapping paths.
- The example app can schedule a short Android alarm and display received events for proof.

---

## File Map

### Android runtime and transport

- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmPlugin.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmReceiver.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/Messages.g.kt` (generated)
- Modify: `warm_alarm_android/lib/src/messages.g.dart` (generated)
- Modify: `warm_alarm_android/pigeons/messages.dart`

### Dart wrapper, example, and tests

- Modify: `warm_alarm_android/lib/warm_alarm_android.dart`
- Modify: `warm_alarm_android/test/warm_alarm_android_test.dart`
- Modify: `warm_alarm/test/warm_alarm_test.dart` only if facade coverage needs to reflect Android runtime signals
- Modify: `warm_alarm/example/lib/main.dart`
- Modify: `warm_alarm/example/integration_test/app_test.dart`

---

### Task 1: Add failing Android wrapper tests for scheduling, snapshots, and failure events

**Files:**

- Modify: `warm_alarm_android/test/warm_alarm_android_test.dart`

- [x] **Step 1: Write failing tests for schedule/cancel/snapshots and failed-event mapping**

```dart
test('scheduleAlarm maps schedule result warning and readiness', () async {
  final api = _MockWarmAlarmApi();
  final platform = WarmAlarmAndroid(api: api);

  final schedule = WarmAlarmSchedule(
    id: 9,
    scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
    notification: const WarmAlarmNotification(title: 'Alarm', body: 'Wake up'),
    audio: const WarmAlarmAudio(filePath: '/tmp/alarm.m4a'),
    snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
  );

  when(() => api.scheduleAlarm(any())).thenAnswer(
    (_) async => WarmAlarmScheduleResultWire(
      alarmId: 9,
      readiness: WarmAlarmReadinessWire(
        level: WarmAlarmReadinessLevelWire.limited,
        reasons: <WarmAlarmReadinessReasonWire>[
          WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied,
        ],
      ),
      warning: WarmAlarmWarningWire(message: 'Exact alarm permission missing.'),
    ),
  );

  final result = await platform.scheduleAlarm(schedule);

  expect(result.alarmId, 9);
  expect(result.readiness.level, WarmAlarmReadinessLevel.limited);
  expect(result.warning?.message, 'Exact alarm permission missing.');
});

test('getScheduledAlarms maps snapshots from wire', () async {
  final api = _MockWarmAlarmApi();
  final platform = WarmAlarmAndroid(api: api);
  final now = DateTime.now().millisecondsSinceEpoch;

  when(api.getScheduledAlarms).thenAnswer(
    (_) async => <WarmAlarmSnapshotWire>[
      WarmAlarmSnapshotWire(id: 3, scheduledAtMillis: now),
    ],
  );

  final snapshots = await platform.getScheduledAlarms();

  expect(snapshots, hasLength(1));
  expect(snapshots.single.id, 3);
});

test('emitEvent maps failed event payload', () async {
  final api = _MockWarmAlarmApi();
  final platform = WarmAlarmAndroid(api: api);
  final emitted = <WarmAlarmEvent>[];
  final sub = platform.events.listen(emitted.add);

  await platform.emitEvent(
    WarmAlarmEventWire(
      alarmId: 4,
      type: WarmAlarmEventTypeWire.failed,
      occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
      failure: WarmAlarmFailureWire(
        code: WarmAlarmFailureCodeWire.audioPlaybackFailed,
        message: 'Unable to start media player.',
      ),
    ),
  );

  await Future<void>.delayed(Duration.zero);

  final failed = emitted.single as WarmAlarmFailed;
  expect(failed.failure.code, WarmAlarmFailureCode.audioPlaybackFailed);
  expect(failed.failure.message, 'Unable to start media player.');

  await sub.cancel();
});
```

- [x] **Step 2: Run the Android wrapper tests to verify they fail correctly**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: FAIL because the current wrapper/runtime do not yet guarantee the new scheduling/failure assertions.

- [x] **Step 3: Implement only the minimal Dart-side mapping needed to satisfy the new tests**

```dart
@override
Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) async =>
    _scheduleResultFromWire(await api.scheduleAlarm(_scheduleToWire(schedule)));

@override
Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async =>
    (await api.getScheduledAlarms()).map(_snapshotFromWire).toList(growable: false);
```

- [x] **Step 4: Re-run Android wrapper tests**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: PASS

---

### Task 2: Make Android runtime emit explicit scheduled and failed lifecycle events

**Files:**

- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmPlugin.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmReceiver.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt`

- [x] **Step 1: Add failing event-mapping assertions in the Android wrapper test**

```dart
test('emitEvent maps scheduled event', () async {
  final api = _MockWarmAlarmApi();
  final platform = WarmAlarmAndroid(api: api);
  final emitted = <WarmAlarmEvent>[];
  final sub = platform.events.listen(emitted.add);

  await platform.emitEvent(
    WarmAlarmEventWire(
      alarmId: 1,
      type: WarmAlarmEventTypeWire.scheduled,
      occurredAtMillis: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  await Future<void>.delayed(Duration.zero);

  expect(emitted.single, isA<WarmAlarmScheduled>());
  await sub.cancel();
});
```

- [x] **Step 2: Run the Android wrapper tests to verify the current failure shape**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: FAIL if event translation or native event types are missing/incomplete.

- [x] **Step 3: Emit `scheduled` when Android accepts a schedule and emit `failed` when foreground playback cannot start**

```kotlin
WarmAlarmPlugin.emitEventFromBackground(
  WarmAlarmEventWire(
    alarmId = schedule.id,
    type = WarmAlarmEventTypeWire.SCHEDULED,
    occurredAtMillis = System.currentTimeMillis(),
  ),
)
```

```kotlin
WarmAlarmPlugin.emitEventFromBackground(
  WarmAlarmEventWire(
    alarmId = alarmId,
    type = WarmAlarmEventTypeWire.FAILED,
    occurredAtMillis = System.currentTimeMillis(),
    failure = WarmAlarmFailureWire(
      code = WarmAlarmFailureCodeWire.AUDIO_PLAYBACK_FAILED,
      message = "Unable to start media player.",
    ),
  ),
)
```

- [x] **Step 4: Re-run Android wrapper tests**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: PASS

---

### Task 3: Tighten Android scheduling and service behavior for the one-shot proof loop

**Files:**

- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmPlugin.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt`
- Modify: `warm_alarm_android/android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt`

- [x] **Step 1: Add a failing test for limited scheduling when exact alarms are unavailable**

```dart
test('scheduleAlarm returns limited readiness and warning when exact scheduling is unavailable', () async {
  final api = _MockWarmAlarmApi();
  final platform = WarmAlarmAndroid(api: api);

  when(() => api.scheduleAlarm(any())).thenAnswer(
    (_) async => WarmAlarmScheduleResultWire(
      alarmId: 12,
      readiness: WarmAlarmReadinessWire(
        level: WarmAlarmReadinessLevelWire.limited,
        reasons: <WarmAlarmReadinessReasonWire>[
          WarmAlarmReadinessReasonWire.exactAlarmPermissionDenied,
        ],
      ),
      warning: WarmAlarmWarningWire(
        message: 'SCHEDULE_EXACT_ALARM not granted; alarm may fire late.',
      ),
    ),
  );

  final result = await platform.scheduleAlarm(
    WarmAlarmSchedule(
      id: 12,
      scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
      notification: const WarmAlarmNotification(title: 'Alarm', body: 'Wake up'),
      audio: const WarmAlarmAudio(assetPath: 'assets/alarm.mp3'),
    ),
  );

  expect(result.readiness.level, WarmAlarmReadinessLevel.limited);
  expect(result.warning?.message, contains('may fire late'));
});
```

- [x] **Step 2: Run the Android wrapper tests to verify the current readiness contract**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: FAIL if the current readiness/warning contract remains too coarse.

- [x] **Step 3: Implement the minimal Android runtime corrections for the one-shot proof**

```kotlin
val inexact = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()
val readiness = if (inexact) {
  WarmAlarmReadinessWire(
    level = WarmAlarmReadinessLevelWire.LIMITED,
    reasons = listOf(WarmAlarmReadinessReasonWire.EXACT_ALARM_PERMISSION_DENIED),
  )
} else {
  deriveReadiness(currentPermissionState())
}
```

```kotlin
// getBroadcast with FLAG_UPDATE_CURRENT creates the PendingIntent when missing.
val pending = alarmPendingIntent(schedule.id, PendingIntent.FLAG_UPDATE_CURRENT)!!
```

```kotlin
private fun handleSnooze(alarmId: Long) {
  stopAudio()
  val schedule = WarmAlarmStore.load(this, alarmId)
  val snoozeDurationMillis = schedule?.snooze?.durationMillis ?: (5L * 60 * 1000)
  val fireAt = System.currentTimeMillis() + snoozeDurationMillis
  WarmAlarmPlugin.rescheduleAlarm(this, alarmId, fireAt)
  WarmAlarmPlugin.emitEventFromBackground(
    WarmAlarmEventWire(
      alarmId = alarmId,
      type = WarmAlarmEventTypeWire.SNOOZED,
      occurredAtMillis = System.currentTimeMillis(),
      snoozeDurationMillis = snoozeDurationMillis,
    ),
  )
}
```

- [x] **Step 4: Re-run Android wrapper tests**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Expected: PASS

---

### Task 4: Turn the example app into a Phase 1B Android proof harness

**Files:**

- Modify: `warm_alarm/example/lib/main.dart`
- Modify: `warm_alarm/example/integration_test/app_test.dart`

- [x] **Step 1: Add a failing integration test for the schedule/event proof surface**

```dart
testWidgets('shows schedule result and event log entries', (tester) async {
  app.main();
  await tester.pumpAndSettle();

  await tester.tap(find.text('Schedule 1 minute alarm'));
  await tester.pumpAndSettle();

  expect(find.textContaining('Scheduled alarm id:'), findsOneWidget);
  expect(find.textContaining('Readiness:'), findsOneWidget);
});
```

- [x] **Step 2: Run the integration test to verify it fails**

Run: `flutter test warm_alarm/example/integration_test/app_test.dart`

Expected: FAIL because the example app currently only inspects readiness and exact scheduling.

- [x] **Step 3: Update the example UI to schedule a short alarm and display incoming events**

```dart
final schedule = WarmAlarmSchedule(
  id: 42,
  scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
  notification: const WarmAlarmNotification(
    title: 'Warm Alarm',
    body: 'Phase 1B proof',
    stopActionTitle: 'Stop',
    snoozeActionTitle: 'Snooze',
  ),
  audio: const WarmAlarmAudio(assetPath: 'assets/demo_alarm.mp3'),
  snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
);

final result = await WarmAlarm.scheduleAlarm(schedule);
setState(() {
  _lastScheduledAlarmId = result.alarmId;
  _lastReadiness = result.readiness.level.name;
});

_subscription ??= WarmAlarm.events.listen((event) {
  setState(() => _events.insert(0, '${event.runtimeType} #${event.alarmId}'));
});
```

- [x] **Step 4: Re-run the integration test**

Run: `flutter test warm_alarm/example/integration_test/app_test.dart`

Expected: PASS

---

### Task 5: Execute Phase 1B verification commands and collect Android proof evidence

**Files:**

- Modify: `docs/specs/2026-04-26-warm-alarm-plugin-design.md` only if implementation forces a correction
- Test: Android package, integration surface, and example app builds

- [x] **Step 1: Run targeted Dart tests**

Run: `flutter test warm_alarm_android/test/warm_alarm_android_test.dart`

Run: `flutter test warm_alarm/test/warm_alarm_test.dart`

Run: `flutter test warm_alarm/example/integration_test/app_test.dart`

Expected: all PASS

- [x] **Step 2: Regenerate bindings, format, and rerun the workspace tests**

Run: `melos run generate`

Run: `melos run format`

Run: `melos run test`

Expected: all commands exit 0

- [x] **Step 3: Build the Android example app**

Run: `flutter build apk --debug`

Workdir: `warm_alarm/example`

Expected: `app-debug.apk` built successfully

- [x] **Step 4: Manual Android proof on a connected device**

Run app on device, then verify these scenarios with captured logs/screenshots:

```plaintext
1. App foreground: schedule a 1-minute alarm and confirm fired audio + Dart event.
2. App background: press Home, wait for the same proof.
3. Task removed: swipe away the app, confirm the alarm still fires or document the exact observed behavior.
4. Local file path: confirm file-based playback works when configured.
5. Stop/Snooze actions: confirm the event stream logs WarmAlarmStopped / WarmAlarmSnoozed.
```

Suggested capture commands:

```plaintext
adb shell dumpsys alarm
adb logcat -v time *:S flutter:D WarmAlarm:D
```

- [x] **Step 5: Record the product-proof result**

Document whether Phase 1B is:

```plaintext
implementation accepted
product proof accepted
or product proof pending manual verification follow-up
```

## Self-Review Notes

- Spec coverage: this plan stays inside Phase 1B Android proof and does not pull wake-check/retrigger into the implementation scope.
- File accuracy: every task points at current `warm_alarm_android`, `warm_alarm`, and example files that already exist in this repo.
- Boundary discipline: all work keeps public models hand-written and generated Pigeon DTOs private to the implementation package.
