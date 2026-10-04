import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_example/main.dart' as example;

void main() {
  late WarmAlarmPlatform originalPlatform;
  late _InspectionPlatform platform;

  setUp(() {
    originalPlatform = WarmAlarmPlatform.instance;
    platform = _InspectionPlatform();
    WarmAlarmPlatform.instance = platform;
  });

  tearDown(() => WarmAlarmPlatform.instance = originalPlatform);

  testWidgets('inspection exposes capability differences and readiness reasons', (tester) async {
    await tester.pumpWidget(const example.MyApp());
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

  testWidgets('settings return keeps the old snapshot until resume refreshes inspection', (tester) async {
    await tester.pumpWidget(const example.MyApp());
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
    await tester.pumpWidget(const example.MyApp());
    await _press(tester, 'Schedule 1 minute alarm');

    expect(find.text('Schedule warning code: unsupportedWakeCheck'), findsOneWidget);
    expect(find.text('Schedule warning: Wake-check is not supported on iOS. Native warning.'), findsOneWidget);
    expect(platform.scheduledAlarm?.wakeCheck, isNotNull);
  });

  testWidgets('a warning without a code stays distinct from no warning', (tester) async {
    platform.warning = const WarmAlarmWarning(message: 'Native warning.');
    await tester.pumpWidget(const example.MyApp());
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
  final button = find.widgetWithText(ElevatedButton, label);
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

  @override
  Future<WarmAlarmReadiness> getReadiness() async => readiness;

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => capabilities;

  @override
  Stream<WarmAlarmEvent> get events => const Stream.empty();

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule) async {
    scheduledAlarm = schedule;
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
