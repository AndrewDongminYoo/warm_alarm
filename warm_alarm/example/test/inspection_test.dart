import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_example/main.dart' as example;
import 'package:warm_alarm_example/voice_audio.dart';

void main() {
  late WarmAlarmPlatform originalPlatform;
  late _InspectionPlatform platform;
  late _FakeVoiceAudio audio;

  setUp(() {
    originalPlatform = WarmAlarmPlatform.instance;
    platform = _InspectionPlatform();
    audio = _FakeVoiceAudio();
    WarmAlarmPlatform.instance = platform;
  });

  tearDown(() async {
    await platform.eventController?.close();
    WarmAlarmPlatform.instance = originalPlatform;
  });

  testWidgets('dashboard scrolls accumulated events independently and reveals permission errors', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    platform
      ..eventController = StreamController<WarmAlarmEvent>.broadcast()
      ..permissionError = PlatformException(code: 'notification_denied');
    await tester.pumpWidget(example.MyApp(audio: audio));
    for (var id = 1; id <= 30; id++) {
      platform.eventController!.add(WarmAlarmScheduled(alarmId: id, occurredAt: DateTime(2026)));
    }
    await tester.pumpAndSettle();
    expect(find.text('WarmAlarmScheduled #1'), findsNothing);
    expect(find.text('WarmAlarmScheduled #11'), findsOneWidget);
    await tester.ensureVisible(find.text('WarmAlarmScheduled #11'));
    await tester.pumpAndSettle();
    final scheduleBefore = tester.getRect(find.text('Schedule 1 minute alarm'));
    await _press(tester, 'Request notification permission');
    final error = find.text('Could not request notification permission');
    final pane = tester.getRect(find.ancestor(of: error, matching: find.byType(SingleChildScrollView)).first);
    expect(tester.getRect(error).top, greaterThanOrEqualTo(pane.top));
    expect(tester.getRect(error).bottom, lessThanOrEqualTo(pane.bottom));
    expect(tester.getRect(find.text('Schedule 1 minute alarm')), scheduleBefore);
    expect(find.text('WarmAlarmScheduled #30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial file load blocks recording until its result is applied', (tester) async {
    audio.pendingLoad = Completer<VoiceClip?>();
    await tester.pumpWidget(example.MyApp(audio: audio));
    final recordButton = find.widgetWithText(ElevatedButton, 'Record my voice');
    expect(tester.widget<ElevatedButton>(recordButton).onPressed, isNull);
    audio.pendingLoad!.complete(const VoiceClip(path: '/old.wav', duration: Duration(seconds: 3)));
    await tester.pumpAndSettle();
    await _press(tester, 'Record again');
    await _press(tester, 'Save recording');
    await _press(tester, 'Schedule 1 minute alarm');
    expect(platform.scheduledAlarm?.audio.filePath, '/recordings/voice.wav');
  });

  testWidgets('unconfirmed recorder stop keeps the stop control available', (tester) async {
    audio.stopFails = true;
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Record my voice');
    await _press(tester, 'Save recording');
    expect(find.text('Save recording'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Schedule 1 minute alarm')).onPressed,
      isNull,
    );
    audio.stopFails = false;
    await _press(tester, 'Save recording');
    expect(find.text('Your voice is ready.'), findsOneWidget);
  });

  testWidgets('playback stream errors restore preview controls and show recovery', (tester) async {
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Record my voice');
    await _press(tester, 'Save recording');
    await _press(tester, 'Preview voice');
    audio.onError!(PlatformException(code: 'playback_failed'), StackTrace.current);
    await tester.pumpAndSettle();
    expect(find.text('Could not play recording'), findsOneWidget);
    expect(find.text('Preview voice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop groups recording and scheduling within the first viewport', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(example.MyApp(audio: audio));
    await tester.pumpAndSettle();
    final record = tester.getRect(find.text('Record my voice'));
    final schedule = tester.getRect(find.text('Schedule 1 minute alarm'));
    expect(record.left, lessThan(schedule.left));
    expect(schedule.bottom, lessThan(600));
    expect(find.text('Request notification permission'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  const previewDirectory = String.fromEnvironment('DEMO_PREVIEW_DIR');
  testWidgets('16 by 9 dashboard keeps main controls and all capability values visible', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Inspect Alarm API');
    for (final label in [
      'Record my voice',
      'Schedule 1 minute alarm',
      'Request notification permission',
      'Open readiness settings',
      'Events',
      'Exact scheduling: supported',
      'Notification scheduling: supported',
      'Background audio: limited',
      'Full-screen presentation: supported',
      'Wake-check: supported',
      'Live Activity: unsupported',
    ]) {
      final bounds = tester.getRect(find.text(label));
      expect(bounds.top, greaterThanOrEqualTo(0), reason: label);
      expect(bounds.bottom, lessThanOrEqualTo(680), reason: label);
    }
    await _press(tester, 'Record my voice');
    await _press(tester, 'Save recording');
    expect(tester.getRect(find.text('Preview voice')).bottom, lessThan(720));
    await _press(tester, 'Schedule 1 minute alarm');
    expect(tester.getRect(find.text('Cancel alarm')).bottom, lessThan(720));
    expect(tester.takeException(), isNull);
  });

  if (previewDirectory.isNotEmpty) {
    testWidgets('export rendered demo fixtures', (tester) async {
      const fontDirectory = String.fromEnvironment('DEMO_FONT_DIR');
      for (final (family, filename) in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf'),
      ]) {
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(File('$fontDirectory/$filename').readAsBytesSync())));
        await loader.load();
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final captureKey = GlobalKey();
      for (final (name, size, brightness, scale) in [
        ('desktop', const Size(800, 600), Brightness.light, 1.0),
        ('dashboard', const Size(1280, 720), Brightness.light, 1.0),
        ('dashboard-scheduled', const Size(1280, 720), Brightness.light, 1.0),
        ('phone', const Size(430, 932), Brightness.light, 1.0),
        ('dark', const Size(800, 600), Brightness.dark, 1.0),
        ('permission-error', const Size(430, 932), Brightness.light, 1.0),
        ('large-text-error', const Size(320, 800), Brightness.light, 2.0),
      ]) {
        await tester.pumpWidget(const SizedBox());
        platform = _InspectionPlatform();
        audio = _FakeVoiceAudio();
        WarmAlarmPlatform.instance = platform;
        if (name.startsWith('dashboard')) {
          platform
            ..readiness = const WarmAlarmReadiness(
              level: WarmAlarmReadinessLevel.blocked,
              reasons: [
                WarmAlarmReadinessReason.notificationPermissionDenied,
                WarmAlarmReadinessReason.backgroundExecutionLimited,
              ],
            )
            ..capabilities = const WarmAlarmCapabilities(
              exactScheduling: WarmAlarmSupportStatus.unsupported,
              notificationScheduling: WarmAlarmSupportStatus.supported,
              backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
              fullScreenPresentation: WarmAlarmSupportStatus.unsupported,
              wakeCheck: WarmAlarmSupportStatus.unsupported,
              liveActivity: WarmAlarmSupportStatus.unsupported,
            )
            ..warning = const WarmAlarmWarning(
              code: WarmAlarmWarningCode.unsupportedWakeCheck,
              message: 'Wake-check is not supported on macOS.',
            );
        }
        tester.view.physicalSize = size;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: example.MyApp(audio: audio),
          ),
        );
        await tester.pumpAndSettle();
        if (name.startsWith('dashboard')) {
          await _press(tester, 'Inspect Alarm API');
          if (name.endsWith('scheduled')) {
            await _press(tester, 'Record my voice');
            await _press(tester, 'Save recording');
            await _press(tester, 'Schedule 1 minute alarm');
            final resultViewport = tester.getRect(
              find
                  .ancestor(
                    of: find.text('Schedule warning: Wake-check is not supported on macOS.'),
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
            );
            expect(
              tester.getRect(find.text('Acceptance does not guarantee future delivery.')).bottom,
              lessThanOrEqualTo(resultViewport.bottom),
            );
          }
        }
        if (name.endsWith('error')) {
          platform.permissionError = PlatformException(code: 'notification_denied');
          await _press(tester, 'Request notification permission');
        }
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(previewDirectory).create(recursive: true);
          await File('$previewDirectory/$name.png').writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('notification request failure shows a short recovery message instead of native details', (tester) async {
    platform.permissionError = PlatformException(
      code: 'Error Domain=UNErrorDomain Code=1',
      message: 'Notifications are not allowed for this application',
      details: 'UserInfo=NSLocalizedDescription, native stack ' * 100,
    );
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Request notification permission');

    expect(find.text('Could not request notification permission'), findsOneWidget);
    expect(find.text('Check notification settings in System Settings, then inspect again.'), findsOneWidget);
    expect(find.textContaining('UserInfo='), findsNothing);
    expect(tester.getRect(find.text('Could not request notification permission')).top, greaterThanOrEqualTo(0));
    expect(tester.getRect(find.text('Could not request notification permission')).bottom, lessThan(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspection exposes capability differences and readiness reasons', (tester) async {
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Inspect Alarm API');

    expect(find.text('Readiness: limited'), findsOneWidget);
    expect(find.text('Readiness reasons: notificationPermissionDenied'), findsOneWidget);
    expect(find.text('Exact scheduling: supported'), findsOneWidget);
    expect(find.text('Notification scheduling: supported'), findsOneWidget);
    expect(find.text('Background audio: limited'), findsOneWidget);
    expect(find.text('Full-screen presentation: supported'), findsOneWidget);
    expect(find.text('Wake-check: supported'), findsOneWidget);
    expect(find.text('Live Activity: unsupported'), findsOneWidget);
    expect(find.textContaining('Schedule warning'), findsNothing);
  });

  testWidgets('a recorded voice can be previewed and prepared for the alarm', (tester) async {
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Record my voice');
    expect(find.textContaining('Recording 0:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await _press(tester, 'Save recording');
    expect(find.text('Your voice is ready.'), findsOneWidget);

    await _press(tester, 'Preview voice');
    expect(find.text('Stop preview'), findsOneWidget);
    audio.onComplete!();
    await tester.pumpAndSettle();
    expect(find.text('Preview voice'), findsOneWidget);

    await _press(tester, 'Schedule 1 minute alarm');
    expect(platform.scheduledAlarm?.audio.filePath, '/recordings/voice.wav');
    expect(platform.scheduledAlarm?.audio.assetPath, isNull);
    expect(platform.preparedPrimary, '/recordings/voice.wav');
    expect(platform.scheduledAlarm?.audio.systemSoundFilePath, '/Library/Sounds/prepared.caf');
    expect(find.text('Alarm request accepted'), findsOneWidget);

    await _press(tester, 'Cancel alarm');
    expect(platform.canceledId, 42);
    expect(find.text('Alarm canceled or stopped'), findsOneWidget);
  });

  testWidgets('microphone denial leaves the demo chime available without leaking details', (tester) async {
    audio.startError = PlatformException(code: 'microphone_denied', details: 'private native stack');
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Record my voice');
    expect(find.text('Could not start recording'), findsOneWidget);
    expect(find.textContaining('private native stack'), findsNothing);
    expect(find.text('Save recording'), findsNothing);
    await _press(tester, 'Schedule 1 minute alarm');
    expect(platform.scheduledAlarm?.audio.assetPath, 'assets/audio/alarm_ring.wav');
  });

  testWidgets('all warnings are visible and a later successful request clears them', (tester) async {
    platform.warnings = const [
      WarmAlarmWarning(code: WarmAlarmWarningCode.unsupportedWakeCheck, message: 'Wake-check is unavailable.'),
      WarmAlarmWarning(message: 'Additional backend diagnostic.'),
    ];
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Schedule 1 minute alarm');
    expect(find.text('Schedule warning: Wake-check is unavailable.'), findsOneWidget);
    expect(find.text('Schedule warning: Additional backend diagnostic.'), findsOneWidget);
    platform.warnings = const [];
    await _press(tester, 'Schedule 1 minute alarm');
    expect(find.text('Schedule warning: Additional backend diagnostic.'), findsNothing);
    expect(find.text('Schedule warning code: none'), findsOneWidget);
  });

  testWidgets('phone layout supports large text and long warnings', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    platform.warning = WarmAlarmWarning(message: 'A longer platform explanation. ' * 10);
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Schedule 1 minute alarm');
    await _press(tester, 'Inspect Alarm API');
    expect(tester.takeException(), isNull);
    expect(find.text('Schedule warning: ${platform.warning!.message}'), findsOneWidget);
  });

  testWidgets('settings return keeps the old snapshot until resume refreshes inspection', (tester) async {
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Inspect Alarm API');
    await _press(tester, 'Open readiness settings');

    expect(find.text('Readiness reasons: notificationPermissionDenied'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    platform
      ..readiness = const WarmAlarmReadiness(level: WarmAlarmReadinessLevel.ready, reasons: [])
      ..capabilities = const WarmAlarmCapabilities(
        exactScheduling: WarmAlarmSupportStatus.limited,
        notificationScheduling: WarmAlarmSupportStatus.supported,
        backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
        fullScreenPresentation: WarmAlarmSupportStatus.supported,
        wakeCheck: WarmAlarmSupportStatus.supported,
        liveActivity: WarmAlarmSupportStatus.unsupported,
      );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Readiness: ready'), findsOneWidget);
    expect(find.text('Readiness reasons: none'), findsOneWidget);
    expect(find.text('Readiness reasons: notificationPermissionDenied'), findsNothing);
    expect(find.text('Exact scheduling: limited'), findsOneWidget);
  });

  testWidgets('scheduling exposes the warning code and preserves its full message', (tester) async {
    platform.warning = const WarmAlarmWarning(
      code: WarmAlarmWarningCode.unsupportedWakeCheck,
      message: 'Wake-check is not supported on iOS. Native warning.',
    );
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Schedule 1 minute alarm');

    expect(find.text('Schedule warning code: unsupportedWakeCheck'), findsOneWidget);
    expect(find.text('Schedule warning: Wake-check is not supported on iOS. Native warning.'), findsOneWidget);
    expect(platform.scheduledAlarm?.wakeCheck, isNotNull);
  });

  testWidgets('a warning without a code stays distinct from no warning', (tester) async {
    platform.warning = const WarmAlarmWarning(message: 'Native warning.');
    await tester.pumpWidget(example.MyApp(audio: audio));
    await _press(tester, 'Schedule 1 minute alarm');

    expect(find.text('Schedule warning code: unclassified'), findsOneWidget);
    expect(find.text('Schedule warning: Native warning.'), findsOneWidget);

    platform.warning = null;
    await _press(tester, 'Schedule 1 minute alarm');

    expect(find.text('Schedule warning code: none'), findsOneWidget);
    expect(find.text('Schedule warning: none'), findsOneWidget);
    expect(find.text('Schedule warning: Native warning.'), findsNothing);
  });
}

Future<void> _press(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  if ((label == 'Request notification permission' || label == 'Open readiness settings') &&
      find.text('Show platform details').evaluate().isNotEmpty) {
    await _press(tester, 'Show platform details');
  }
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _InspectionPlatform extends WarmAlarmPlatform {
  WarmAlarmReadiness readiness = const WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.limited,
    reasons: [WarmAlarmReadinessReason.notificationPermissionDenied],
  );
  WarmAlarmCapabilities capabilities = const WarmAlarmCapabilities(
    exactScheduling: WarmAlarmSupportStatus.supported,
    notificationScheduling: WarmAlarmSupportStatus.supported,
    backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
    fullScreenPresentation: WarmAlarmSupportStatus.supported,
    wakeCheck: WarmAlarmSupportStatus.supported,
    liveActivity: WarmAlarmSupportStatus.unsupported,
  );
  WarmAlarmWarning? warning;
  WarmAlarmSchedule? scheduledAlarm;
  PlatformException? permissionError;
  List<WarmAlarmWarning>? warnings;
  String? preparedPrimary;
  int? canceledId;
  StreamController<WarmAlarmEvent>? eventController;

  @override
  Future<String?> prepareSystemSound({required String primaryFilePath, String? backgroundAssetPath}) async {
    preparedPrimary = primaryFilePath;
    return '/Library/Sounds/prepared.caf';
  }

  @override
  Future<void> cancelAlarm(int id) async => canceledId = id;

  @override
  Future<WarmAlarmRemediationResult> requestNotificationPermission() async {
    if (permissionError case final error?) throw error;
    return WarmAlarmRemediationResult(
      status: WarmAlarmRemediationStatus.completed,
      permissionState: const WarmAlarmPermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        fullScreenIntentGranted: true,
      ),
      readiness: readiness,
    );
  }

  @override
  Future<WarmAlarmReadiness> getReadiness() async => readiness;

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => capabilities;

  @override
  Stream<WarmAlarmEvent> get events => eventController?.stream ?? const Stream.empty();

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) async {
    scheduledAlarm = schedule;
    if (warnings case final values?) {
      return WarmAlarmScheduleResult.withWarnings(alarmId: schedule.id, readiness: readiness, warnings: values);
    }
    return WarmAlarmScheduleResult(alarmId: schedule.id, readiness: readiness, warning: warning);
  }

  @override
  Future<WarmAlarmRemediationResult> openReadinessSettings(WarmAlarmReadinessReason reason) async {
    if (reason != WarmAlarmReadinessReason.notificationPermissionDenied) {
      throw ArgumentError.value(reason, 'reason');
    }
    return WarmAlarmRemediationResult(
      status: WarmAlarmRemediationStatus.completed,
      permissionState: const WarmAlarmPermissionState(
        notificationsGranted: false,
        exactAlarmGranted: true,
        fullScreenIntentGranted: true,
      ),
      readiness: readiness,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoiceAudio extends VoiceAudio {
  PlatformException? startError;
  void Function()? onComplete;
  void Function(Object, StackTrace)? onError;
  Completer<VoiceClip?>? pendingLoad;
  bool recording = false;
  bool stopFails = false;

  @override
  bool get isRecording => recording;

  @override
  Future<VoiceClip?> load() async => pendingLoad == null ? null : await pendingLoad!.future;

  @override
  Future<void> startRecording() async {
    if (startError case final error?) throw error;
    recording = true;
  }

  @override
  Future<VoiceClip> stopRecording(Duration duration) async {
    if (stopFails) throw PlatformException(code: 'stop_failed');
    recording = false;
    return VoiceClip(path: '/recordings/voice.wav', duration: duration);
  }

  @override
  Future<void> preview(
    String path, {
    required void Function() onComplete,
    required void Function(Object, StackTrace) onError,
  }) async {
    this.onComplete = onComplete;
    this.onError = onError;
  }

  @override
  Future<void> stopPreview() async {}

  @override
  Future<void> dispose() async {}
}
