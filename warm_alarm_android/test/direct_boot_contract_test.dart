import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alarm receiver and playback service are Direct Boot aware', () {
    final manifest = File(
      'android/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        '<receiver\n            android:name=".WarmAlarmReceiver"\n            android:directBootAware="true"',
      ),
    );
    expect(
      manifest,
      contains(
        '<service\n            android:name=".WarmAlarmForegroundService"\n            android:directBootAware="true"',
      ),
    );
  });

  test('Direct Boot alarm reads schedules from device-protected storage', () {
    final store = File(
      'android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt',
    ).readAsStringSync();

    expect(
      store,
      contains(
        'WarmAlarmDirectBoot.storageContext(context).getSharedPreferences',
      ),
    );
  });

  test('Direct Boot alarm skips credential-protected voice files', () {
    final service = File(
      'android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt',
    ).readAsStringSync();

    expect(
      service,
      contains('WarmAlarmDirectBoot.canReadCredentialProtectedFiles(this)'),
    );
  });
}
