// Scripted walkthrough for recording the example on Android and iOS.
//
// Drives the same steps with the same pacing on every device, so screen recordings made on separate devices line up
// stage by stage: 01 Readiness -> 02 Record -> 03 Schedule -> 04 Alarm.
//
// This is not a test suite. The file name has no `_test` suffix, so `flutter test integration_test` does not pick it
// up. An app built with this file as its entrypoint runs the script every time it launches.
//
// Android: build with `flutter build apk --profile -t integration_test/recording_demo.dart`, install it with
// `adb install -r` so granted permissions survive, and launch the app while `adb shell screenrecord` runs.
// `flutter drive` reinstalls the app and resets its permissions, which stops the script at the microphone prompt.
//
// iOS: run `flutter run --profile -t integration_test/recording_demo.dart -d <device>`. Grant the microphone and local
// network prompts first, and disconnect Xcode DeviceHub: while it mirrors the device, recordings contain no audio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:warm_alarm_example/main.dart' as app;

const _scroll = Duration(milliseconds: 900);
const _beat = Duration(milliseconds: 1200);
const _read = Duration(milliseconds: 3500);
const _recordLength = Duration(seconds: 10);
const _ringFor = Duration(seconds: 8);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('recording demo', (tester) async {
    Future<void> hold(Duration duration) async {
      await Future<void>.delayed(duration);
      await tester.pump();
    }

    Future<void> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
      final deadline = DateTime.now().add(timeout);
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('Timed out waiting for $finder');
        }
        await hold(const Duration(milliseconds: 100));
      }
    }

    // Scrolls so the target sits at the same relative height on every device.
    Future<void> reveal(Finder finder, {double alignment = 0.3}) async {
      await waitFor(finder);
      await Scrollable.ensureVisible(
        tester.element(finder.first),
        alignment: alignment,
        duration: _scroll,
        curve: Curves.easeInOut,
      );
      await hold(const Duration(milliseconds: 200));
    }

    Future<void> tap(Finder finder) async {
      await tester.tap(finder.first);
      await tester.pump();
    }

    app.main();
    await waitFor(find.text('Your voice, your alarm.'));
    // Lead-in so both recordings have the untouched first screen.
    await hold(const Duration(seconds: 5));

    // 01 / Readiness
    await reveal(find.text('Inspect Alarm API'), alignment: 0.35);
    await hold(_beat);
    await tap(find.text('Inspect Alarm API'));
    // Inspecting expands the platform details on its own.
    await waitFor(find.textContaining('Readiness: '));
    await hold(_beat);
    await reveal(find.textContaining('Wake-check: '), alignment: 0.6);
    await hold(_read);

    // 02 / Record
    final record = find.textContaining(RegExp(r'^Record (again|my voice)$'));
    await reveal(record, alignment: 0.45);
    await hold(_beat);
    await tap(record);
    await waitFor(find.text('Save recording'));
    await hold(_recordLength);
    await tap(find.text('Save recording'));
    await waitFor(find.text('Your voice is ready.'));
    await hold(_beat);

    // 03 / Schedule
    await reveal(find.text('My voice'), alignment: 0.2);
    await hold(_beat);
    await tap(find.text('My voice'));
    await hold(_beat);
    final wakeCheck = find.byType(SwitchListTile);
    if (!tester.widget<SwitchListTile>(wakeCheck).value) {
      await tap(wakeCheck);
      await hold(_beat);
    }
    await tap(find.text('Schedule 1 minute alarm'));
    await waitFor(find.textContaining('Schedule warning code: '));
    await reveal(find.text('Alarm request accepted'), alignment: 0.2);
    await hold(const Duration(seconds: 6));

    // 04 / Alarm
    await reveal(find.text('Events'), alignment: 0.25);
    await waitFor(find.textContaining('WarmAlarmFired'), timeout: const Duration(seconds: 90));
    await hold(_ringFor);
    await reveal(find.text('Cancel alarm'), alignment: 0.4);
    await tap(find.text('Cancel alarm'));
    await hold(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
