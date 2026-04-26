import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:warm_alarm_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E', () {
    testWidgets('inspects the warm alarm api surface', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inspect Alarm API'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Readiness: ${expectedReadiness()}'));
      await tester.ensureVisible(
        find.text('Exact scheduling: ${expectedExactScheduling()}'),
      );
    });
  });
}

String expectedReadiness() {
  if (Platform.isAndroid) return 'blocked';
  if (Platform.isIOS) return 'limited';
  if (Platform.isMacOS) return 'limited';
  throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
}

String expectedExactScheduling() {
  if (Platform.isAndroid) return 'supported';
  if (Platform.isIOS) return 'limited';
  if (Platform.isMacOS) return 'unsupported';
  throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
}
