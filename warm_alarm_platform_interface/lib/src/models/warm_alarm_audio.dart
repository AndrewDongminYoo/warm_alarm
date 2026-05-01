import 'package:warm_alarm_platform_interface/src/models/warm_alarm_volume_fade_step.dart';

final class WarmAlarmAudio {
  const WarmAlarmAudio({
    this.filePath,
    this.assetPath,
    this.loop = true,
    this.volume,
    this.fadeInDuration,
    this.fadeSteps,
    this.volumeEnforced = false,
    this.vibrate = true,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final Duration? fadeInDuration;
  final List<WarmAlarmVolumeFadeStep>? fadeSteps;
  final bool volumeEnforced;
  final bool vibrate;
}
