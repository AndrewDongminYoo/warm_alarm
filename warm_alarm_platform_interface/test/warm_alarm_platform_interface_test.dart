import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

class WarmAlarmMock extends WarmAlarmPlatform {
  final _events = StreamController<WarmAlarmEvent>.broadcast();

  @override
  Future<void> cancelAlarm(int id) async {}

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Stream<WarmAlarmEvent> get events => _events.stream;

  @override
  Future<WarmAlarmCapabilities> getCapabilities() async => const WarmAlarmCapabilities(
    exactScheduling: WarmAlarmSupportStatus.supported,
    notificationScheduling: WarmAlarmSupportStatus.supported,
    backgroundAudioPlayback: WarmAlarmSupportStatus.limited,
    fullScreenPresentation: WarmAlarmSupportStatus.unsupported,
    wakeCheck: WarmAlarmSupportStatus.unsupported,
    liveActivity: WarmAlarmSupportStatus.unsupported,
  );

  @override
  Future<WarmAlarmPermissionState> getPermissionState() async => const WarmAlarmPermissionState(
    notificationsGranted: true,
    exactAlarmGranted: false,
    fullScreenIntentGranted: false,
  );

  @override
  Future<WarmAlarmReadiness> getReadiness() async => const WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.limited,
    reasons: <WarmAlarmReadinessReason>[
      WarmAlarmReadinessReason.exactAlarmPermissionDenied,
    ],
  );

  @override
  Future<List<WarmAlarmSnapshot>> getScheduledAlarms() async => const <WarmAlarmSnapshot>[];

  @override
  Future<bool> isRinging({int? id}) async => false;

  @override
  Future<void> setKillWarning({
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> clearKillWarning() async {}

  @override
  Future<WarmAlarmScheduleResult> scheduleAlarm(
    WarmAlarmSchedule schedule,
  ) async => const WarmAlarmScheduleResult(
    alarmId: 7,
    readiness: WarmAlarmReadiness(
      level: WarmAlarmReadinessLevel.limited,
      reasons: <WarmAlarmReadinessReason>[
        WarmAlarmReadinessReason.backgroundExecutionLimited,
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WarmAlarmWakeCheck', () {
    test('constructs with required checkDelay and defaults', () {
      const check = WarmAlarmWakeCheck(checkDelay: Duration(minutes: 5));
      expect(check.checkDelay, const Duration(minutes: 5));
      expect(check.retriggerDelay, isNull);
      expect(check.maxRetriggers, 1);
    });

    test('accepts optional retrigger config', () {
      const check = WarmAlarmWakeCheck(
        checkDelay: Duration(minutes: 5),
        retriggerDelay: Duration(minutes: 2),
        maxRetriggers: 3,
      );
      expect(check.retriggerDelay, const Duration(minutes: 2));
      expect(check.maxRetriggers, 3);
    });
  });

  group('WarmAlarmSchedule wakeCheck field', () {
    test('schedule accepts optional wakeCheck', () {
      final schedule = WarmAlarmSchedule(
        id: 1,
        scheduledAt: DateTime(2026, 5, 1, 7),
        notification: const WarmAlarmNotification(title: 'T', body: 'B'),
        audio: const WarmAlarmAudio(),
        wakeCheck: const WarmAlarmWakeCheck(checkDelay: Duration(minutes: 5)),
      );
      expect(schedule.wakeCheck!.checkDelay.inMinutes, 5);
    });

    test('schedule wakeCheck defaults to null', () {
      final schedule = WarmAlarmSchedule(
        id: 2,
        scheduledAt: DateTime(2026, 5, 1, 7),
        notification: const WarmAlarmNotification(title: 'T', body: 'B'),
        audio: const WarmAlarmAudio(),
      );
      expect(schedule.wakeCheck, isNull);
    });
  });

  group('Wake-check event types', () {
    final at = DateTime(2026, 5, 1, 7, 5);

    test('WarmAlarmWakeCheckShown extends WarmAlarmEvent', () {
      final event = WarmAlarmWakeCheckShown(alarmId: 1, occurredAt: at);
      expect(event.alarmId, 1);
      expect(event.occurredAt, at);
    });

    test('WarmAlarmWakeCheckDismissed extends WarmAlarmEvent', () {
      expect(
        WarmAlarmWakeCheckDismissed(alarmId: 2, occurredAt: at),
        isA<WarmAlarmEvent>(),
      );
    });

    test('WarmAlarmWakeCheckExpired extends WarmAlarmEvent', () {
      expect(
        WarmAlarmWakeCheckExpired(alarmId: 3, occurredAt: at),
        isA<WarmAlarmEvent>(),
      );
    });

    test('WarmAlarmRetriggered extends WarmAlarmEvent', () {
      expect(
        WarmAlarmRetriggered(alarmId: 4, occurredAt: at),
        isA<WarmAlarmEvent>(),
      );
    });
  });

  test('WarmAlarmPlatform exposes typed scheduling APIs', () async {
    final platform = WarmAlarmMock();
    WarmAlarmPlatform.instance = platform;

    expect(
      await WarmAlarmPlatform.instance.getCapabilities(),
      isA<WarmAlarmCapabilities>(),
    );
    expect(
      await WarmAlarmPlatform.instance.getPermissionState(),
      isA<WarmAlarmPermissionState>(),
    );
    expect(
      await WarmAlarmPlatform.instance.getReadiness(),
      isA<WarmAlarmReadiness>(),
    );
  });

  group('A1+N1+W1 models', () {
    test('WarmAlarmVolumeFadeStep constructs with time and volume', () {
      const step = WarmAlarmVolumeFadeStep(
        time: Duration(seconds: 3),
        volume: 0.5,
      );
      expect(step.time, const Duration(seconds: 3));
      expect(step.volume, 0.5);
    });

    test('WarmAlarmAudio accepts fadeSteps and volumeEnforced', () {
      const audio = WarmAlarmAudio(
        volumeEnforced: true,
        fadeSteps: <WarmAlarmVolumeFadeStep>[
          WarmAlarmVolumeFadeStep(time: Duration.zero, volume: 0.2),
          WarmAlarmVolumeFadeStep(time: Duration(seconds: 5), volume: 1),
        ],
      );
      expect(audio.volumeEnforced, isTrue);
      expect(audio.fadeSteps, hasLength(2));
      expect(audio.fadeSteps!.first.volume, 0.2);
      expect(audio.fadeSteps!.last.time, const Duration(seconds: 5));
    });

    test(
      'WarmAlarmNotification accepts androidIcon, androidIconColor, keepNotificationAfterAlarmEnds',
      () {
        const notif = WarmAlarmNotification(
          title: 'T',
          body: 'B',
          androidIcon: 'ic_alarm_custom',
          androidIconColor: 0xFFFF0000,
          keepNotificationAfterAlarmEnds: true,
        );
        expect(notif.androidIcon, 'ic_alarm_custom');
        expect(notif.androidIconColor, 0xFFFF0000);
        expect(notif.keepNotificationAfterAlarmEnds, isTrue);
      },
    );

    test(
      'setKillWarning and clearKillWarning complete without error',
      () async {
        final platform = WarmAlarmMock();
        WarmAlarmPlatform.instance = platform;
        await expectLater(
          WarmAlarmPlatform.instance.setKillWarning(
            title: 'App killed',
            body: 'Alarm interrupted',
          ),
          completes,
        );
        await expectLater(
          WarmAlarmPlatform.instance.clearKillWarning(),
          completes,
        );
      },
    );
  });
}
