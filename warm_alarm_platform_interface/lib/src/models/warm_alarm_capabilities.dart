import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';

final class WarmAlarmCapabilities {
  const WarmAlarmCapabilities({
    required this.exactScheduling,
    required this.notificationScheduling,
    required this.backgroundAudioPlayback,
    required this.fullScreenPresentation,
    required this.wakeCheck,
    required this.liveActivity,
  });

  final WarmAlarmSupportStatus exactScheduling;
  final WarmAlarmSupportStatus notificationScheduling;
  final WarmAlarmSupportStatus backgroundAudioPlayback;
  final WarmAlarmSupportStatus fullScreenPresentation;
  final WarmAlarmSupportStatus wakeCheck;
  final WarmAlarmSupportStatus liveActivity;
}
