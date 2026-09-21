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

  /// Local audio file path.
  ///
  /// An empty string is treated as absent.
  /// When both [filePath] and [assetPath] are set, [filePath] takes precedence.
  final String? filePath;

  /// Flutter asset path for alarm audio when [filePath] is absent.
  ///
  /// An empty string is treated as absent.
  final String? assetPath;

  /// Complete iOS AlarmKit sound file prepared with `prepareSystemSound`.
  ///
  /// An empty string is treated as absent.
  /// This is an iOS AlarmKit override, not a general-purpose audio source.
  /// Other backends ignore it and continue to use [filePath] or [assetPath].
  final String? systemSoundFilePath;

  /// Whether custom player audio repeats after it finishes.
  ///
  /// Android applies this to an accessible file or asset source.
  /// Its native fallback alarm loops.
  final bool loop;

  /// Initial custom-player volume from 0.0 to 1.0.
  ///
  /// A null value uses the native player default.
  final double? volume;

  /// Optional fade-in hint retained in the native schedule data.
  ///
  /// Current Android, iOS, and macOS playback paths do not apply this value.
  /// Use [fadeSteps] for a fade curve.
  /// Must not be negative.
  final Duration? fadeInDuration;

  /// Optional custom fade breakpoints in strictly increasing millisecond order.
  ///
  /// Each time must be nonnegative and each volume must be from 0.0 to 1.0.
  final List<WarmAlarmVolumeFadeStep>? fadeSteps;

  /// Whether the native implementation attempts to keep alarm audio at full volume.
  ///
  /// Android enforces the alarm stream volume.
  /// Apple platforms can enforce only the plugin-owned player volume and cannot guarantee system volume.
  final bool volumeEnforced;

  /// Whether the native implementation should request vibration or haptics.
  ///
  /// Apple does not support background haptics for scheduled alarms.
  final bool vibrate;
}
