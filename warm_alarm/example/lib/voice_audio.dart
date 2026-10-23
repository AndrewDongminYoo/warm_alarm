import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

final class VoiceClip {
  const new({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

/// Device I/O stays outside the screen so widget tests never request a microphone.
class VoiceAudio {
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<void>? _playbackSubscription;
  bool _recording = false;

  bool get isRecording => _recording;

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    return await Directory('${support.path}/voice_recordings').create(recursive: true);
  }

  Future<VoiceClip?> load() async {
    final metadata = File('${(await _directory()).path}/latest.json');
    if (!metadata.existsSync()) return null;
    final json = jsonDecode(await metadata.readAsString());
    if (json is! Map<String, dynamic> || json['path'] is! String || json['durationMs'] is! int) {
      throw const FormatException('Invalid saved recording.');
    }
    final path = json['path'] as String;
    if (!File(path).existsSync()) return null;
    return VoiceClip(
      path: path,
      duration: Duration(milliseconds: json['durationMs'] as int),
    );
  }

  Future<void> startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw PlatformException(code: 'microphone_denied');
    }
    final directory = await _directory();
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 22050, numChannels: 1),
      path: '${directory.path}/voice-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    _recording = true;
  }

  Future<VoiceClip> stopRecording(Duration duration) async {
    String? path;
    try {
      path = await _recorder?.stop();
      _recording = false;
    } on Exception {
      // Disposal is awaited; keep the active state if native cleanup also fails.
      await _recorder?.dispose();
      _recorder = null;
      _recording = false;
      rethrow;
    }
    if (path == null || !File(path).existsSync() || await File(path).length() <= 44) {
      throw PlatformException(code: 'empty_recording', message: 'The recording contains no audio.');
    }
    final metadata = File('${(await _directory()).path}/latest.json');
    await metadata.writeAsString(jsonEncode({'path': path, 'durationMs': duration.inMilliseconds}), flush: true);
    // Previous recordings remain immutable: a pending alarm can still reference them.
    return VoiceClip(path: path, duration: duration);
  }

  Future<void> preview(
    String path, {
    required void Function() onComplete,
    required void Function(Object, StackTrace) onError,
  }) async {
    final player = _player ??= AudioPlayer();
    await _playbackSubscription?.cancel();
    _playbackSubscription = player.onPlayerComplete.listen((_) => onComplete(), onError: onError);
    await player.play(DeviceFileSource(path));
  }

  Future<void> stopPreview() async {
    await _player?.stop();
  }

  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _recorder?.dispose();
    _recording = false;
    await _player?.dispose();
  }
}
