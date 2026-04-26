import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:warm_alarm_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E', () {
    testWidgets('shows schedule result and event log entries', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Schedule 1 minute alarm'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.textContaining('Scheduled alarm id:'));
      await tester.ensureVisible(find.textContaining('Readiness:'));
      await tester.ensureVisible(find.textContaining('WarmAlarmScheduled #42'));
    });
  });
}
