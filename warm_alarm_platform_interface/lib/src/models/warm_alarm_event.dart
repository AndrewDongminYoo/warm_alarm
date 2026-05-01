import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

sealed class WarmAlarmEvent {
  const WarmAlarmEvent({
    required this.alarmId,
    required this.occurredAt,
  });

  final int alarmId;
  final DateTime occurredAt;
}

final class WarmAlarmScheduled extends WarmAlarmEvent {
  const WarmAlarmScheduled({
    required super.alarmId,
    required super.occurredAt,
  });
}

final class WarmAlarmFired extends WarmAlarmEvent {
  const WarmAlarmFired({
    required super.alarmId,
    required super.occurredAt,
    this.payload,
  });

  final String? payload;
}

final class WarmAlarmStopped extends WarmAlarmEvent {
  const WarmAlarmStopped({
    required super.alarmId,
    required super.occurredAt,
    this.payload,
  });

  final String? payload;
}

final class WarmAlarmSnoozed extends WarmAlarmEvent {
  const WarmAlarmSnoozed({
    required super.alarmId,
    required super.occurredAt,
    required this.duration,
    this.payload,
  });

  final Duration duration;
  final String? payload;
}

final class WarmAlarmFailed extends WarmAlarmEvent {
  const WarmAlarmFailed({
    required super.alarmId,
    required super.occurredAt,
    required this.failure,
  });

  final WarmAlarmFailure failure;
}

final class WarmAlarmWakeCheckShown extends WarmAlarmEvent {
  const WarmAlarmWakeCheckShown({
    required super.alarmId,
    required super.occurredAt,
  });
}

final class WarmAlarmWakeCheckDismissed extends WarmAlarmEvent {
  const WarmAlarmWakeCheckDismissed({
    required super.alarmId,
    required super.occurredAt,
  });
}

final class WarmAlarmWakeCheckExpired extends WarmAlarmEvent {
  const WarmAlarmWakeCheckExpired({
    required super.alarmId,
    required super.occurredAt,
  });
}

final class WarmAlarmRetriggered extends WarmAlarmEvent {
  const WarmAlarmRetriggered({
    required super.alarmId,
    required super.occurredAt,
    this.payload,
  });

  final String? payload;
}
