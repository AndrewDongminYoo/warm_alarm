final class WarmAlarmAudio {
  const WarmAlarmAudio({
    this.filePath,
    this.assetPath,
    this.loop = true,
    this.volume,
    this.fadeInDuration,
    this.vibrate = true,
  });

  final String? filePath;
  final String? assetPath;
  final bool loop;
  final double? volume;
  final Duration? fadeInDuration;
  final bool vibrate;
}
