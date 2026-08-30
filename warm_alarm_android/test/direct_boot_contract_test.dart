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

  test('Direct Boot schedules keep device-protected storage canonical', () {
    final store = File(
      'android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt',
    ).readAsStringSync();

    expect(
      store,
      contains(
        'private fun schedulePrefs(context: Context) = dePrefs(context) ?: prefs(context)',
      ),
    );
  });

  test(
    'Direct Boot retrigger counters keep device-protected storage canonical',
    () {
      final store = File(
        'android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt',
      ).readAsStringSync();

      expect(
        store,
        contains('val retriggerPrefs = schedulePrefs(context)'),
      );
      expect(
        store,
        contains('migrateLegacyRetriggerCount(context, retriggerPrefs, id)'),
      );
      expect(
        store,
        contains('return retriggerPrefs.getInt(retriggerKey(id), 0)'),
      );
      expect(
        store,
        contains(
          'schedulePrefs(context).edit().putInt(retriggerKey(id), current + 1).apply()',
        ),
      );
      expect(store, contains('clearRetriggerCount(context, id)'));
    },
  );

  test('Direct Boot retrigger counters migrate the legacy credential value', () {
    final store = File(
      'android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt',
    ).readAsStringSync();

    expect(store, contains('@Synchronized'));
    expect(store, contains('private fun migrateLegacyRetriggerCount('));
    expect(
      store,
      contains('devicePrefs.getString(retriggerMigrationKey(id), null)'),
    );
    expect(
      store,
      contains('devicePrefs.getBoolean(retriggerTombstoneKey(id), false)'),
    );
    expect(
      store,
      contains(
        'devicePrefs.getInt(retriggerKey(id), 0) + legacyPrefs.getInt(retriggerKey(id), 0)',
      ),
    );
    expect(
      store,
      contains(
        'putString(retriggerMigrationKey(id), RETRIGGER_MIGRATION_IMPORTED)',
      ),
    );
    expect(
      store,
      contains(
        'putString(retriggerMigrationKey(id), RETRIGGER_MIGRATION_COMPLETE)',
      ),
    );
    expect(
      store,
      contains('legacyPrefs.edit().remove(retriggerKey(id)).apply()'),
    );
  });

  test(
    'Direct Boot retrigger removal clears the legacy credential value when available',
    () {
      final store = File(
        'android/src/main/kotlin/com/andrew/alarm/WarmAlarmStore.kt',
      ).readAsStringSync();

      expect(store, contains('private fun clearRetriggerCount('));
      expect(
        store,
        contains(
          '!WarmAlarmDirectBoot.canReadCredentialProtectedFiles(context)',
        ),
      );
      expect(
        store,
        contains(
          'putBoolean(retriggerTombstoneKey(id), true)',
        ),
      );
      expect(
        store,
        contains(
          RegExp(
            r'context\s*\.getSharedPreferences\(PREFS,\s*Context\.MODE_PRIVATE\)\s*'
            r'\.edit\(\)\s*\.remove\(retriggerKey\(id\)\)\s*\.apply\(\)',
          ),
        ),
      );
    },
  );

  test('Direct Boot alarm skips credential-protected voice files', () {
    final service = File(
      'android/src/main/kotlin/com/andrew/alarm/WarmAlarmForegroundService.kt',
    ).readAsStringSync();

    expect(
      service,
      contains('WarmAlarmDirectBoot.canReadCredentialProtectedFiles(this)'),
    );
    expect(service, contains('File(filePath).canRead()'));
  });
}
