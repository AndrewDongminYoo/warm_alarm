import 'package:warm_alarm_platform_interface/src/models/warm_alarm_support.dart';
import 'package:warm_alarm_platform_interface/src/models/warm_alarm_volume_fade_step.dart';

final class WarmAlarmAudio {
  const WarmAlarmAudio({
    this.filePath,
    this.assetPath,
    this.systemSoundFilePath,
    this.loop = true,
    this.volume,
    this.fadeInDuration,
    this.fadeSteps,
    this.volumeEnforced = false,
    this.vibrate = true,
  });

  final String? filePath;
  final String? assetPath;

  /// Complete sound for iOS AlarmKit, prepared before scheduling.
  /// Other backends keep using [filePath] and [assetPath].
  final String? systemSoundFilePath;
  final bool loop;
  final double? volume;

  /// Time for a linear fade from silence to [volume], or to 1.0 when [volume] is null.
  /// When [fadeSteps] is also set, [fadeSteps] wins and this value is ignored.
  /// A backend that does not apply the fade can report [WarmAlarmWarningCode.unsupportedFadeIn].
  /// The current Android, iOS, and macOS backends neither apply this value nor report that code.
  /// Use [fadeSteps] for a fade that plays today.
  final Duration? fadeInDuration;

  /// Explicit volume points for the fade.
  /// When both this and [fadeInDuration] are set, this list wins.
  final List<WarmAlarmVolumeFadeStep>? fadeSteps;
  final bool volumeEnforced;
  final bool vibrate;
}
