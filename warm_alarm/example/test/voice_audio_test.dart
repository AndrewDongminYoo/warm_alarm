import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warm_alarm_example/voice_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  const directoryChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late VoiceAudio audio;
  late List<String> calls;
  late List<MethodChannel> eventChannels;
  String? recordedPath;
  var failStop = false;
  var failDispose = false;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('warm-alarm-audio-test-');
    audio = VoiceAudio();
    calls = [];
    eventChannels = [];
    recordedPath = null;
    failStop = false;
    failDispose = false;
    messenger.setMockMethodCallHandler(directoryChannel, (_) async => directory.path);
    messenger.setMockMethodCallHandler(recordChannel, (call) async {
      calls.add(call.method);
      final arguments = call.arguments as Map<Object?, Object?>;
      switch (call.method) {
        case 'create':
          final events = MethodChannel('com.llfbandit.record/events/${arguments['recorderId']}');
          eventChannels.add(events);
          messenger.setMockMethodCallHandler(events, (_) async => null);
        case 'hasPermission':
          return true;
        case 'start':
          recordedPath = arguments['path']! as String;
          // Synthetic bytes exercise file persistence, not audio encoding or a microphone.
          await File(recordedPath!).writeAsBytes(List<int>.filled(128, 0));
        case 'stop':
          if (failStop) throw PlatformException(code: 'stop_failed');
          return recordedPath;
        case 'dispose':
          if (failDispose) throw PlatformException(code: 'dispose_failed');
      }
      return null;
    });
  });

  tearDown(() async {
    failDispose = false;
    await audio.dispose();
    messenger
      ..setMockMethodCallHandler(recordChannel, null)
      ..setMockMethodCallHandler(directoryChannel, null);
    for (final events in eventChannels) {
      messenger.setMockMethodCallHandler(events, null);
    }
    await directory.delete(recursive: true);
  });

  test('saved clip is restored and previous files survive another recording', () async {
    await audio.startRecording();
    final first = await audio.stopRecording(const Duration(seconds: 2));
    final restored = await audio.load();
    expect(restored?.path, first.path);
    expect(restored?.duration, const Duration(seconds: 2));
    await audio.startRecording();
    final second = await audio.stopRecording(const Duration(seconds: 3));
    expect(second.path, isNot(first.path));
    expect(File(first.path).existsSync(), isTrue);
  });

  test('stop failure awaits native disposal before clearing active state', () async {
    await audio.startRecording();
    failStop = true;
    await expectLater(audio.stopRecording(const Duration(seconds: 2)), throwsA(isA<PlatformException>()));
    expect(calls, containsAllInOrder(['start', 'stop', 'dispose']));
    expect(audio.isRecording, isFalse);
  });

  test('failed native shutdown keeps active state until cleanup can be retried', () async {
    await audio.startRecording();
    failStop = true;
    failDispose = true;
    await expectLater(audio.stopRecording(const Duration(seconds: 2)), throwsA(isA<PlatformException>()));
    expect(audio.isRecording, isTrue);
    failDispose = false;
    await audio.dispose();
    expect(audio.isRecording, isFalse);
  });
}
