import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_android/warm_alarm_android.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android) {
    WarmAlarmAndroid.registerWith();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _readiness;
  String? _exactScheduling;
  int? _lastScheduledAlarmId;
  String? _scheduleWarning;
  final List<String> _events = <String>[];
  StreamSubscription<WarmAlarmEvent>? _eventsSubscription;

  @override
  void initState() {
    super.initState();
    _eventsSubscription = WarmAlarm.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, '${event.runtimeType} #${event.alarmId}');
      });
    });
  }

  @override
  void dispose() {
    unawaited(_eventsSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WarmAlarm Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_readiness == null)
              const SizedBox.shrink()
            else
              Column(
                children: [
                  Text(
                    'Readiness: $_readiness',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Exact scheduling: $_exactScheduling'),
                  if (_lastScheduledAlarmId != null) ...[
                    const SizedBox(height: 8),
                    Text('Scheduled alarm id: $_lastScheduledAlarmId'),
                  ],
                  if (_scheduleWarning != null) ...[
                    const SizedBox(height: 8),
                    Text('Schedule warning: $_scheduleWarning'),
                  ],
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (!context.mounted) return;
                try {
                  final readiness = await WarmAlarm.getReadiness();
                  final capabilities = await WarmAlarm.getCapabilities();
                  setState(() {
                    _readiness = readiness.level.name;
                    _exactScheduling = capabilities.exactScheduling.name;
                  });
                } on Exception catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).primaryColor,
                      content: Text('$error'),
                    ),
                  );
                }
              },
              child: const Text('Inspect Alarm API'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (!context.mounted) return;
                try {
                  final schedule = WarmAlarmSchedule(
                    id: 42,
                    scheduledAt: DateTime.now().add(const Duration(minutes: 1)),
                    notification: const WarmAlarmNotification(
                      title: 'Warm Alarm',
                      body: 'Phase 1B proof',
                      stopActionTitle: 'Stop',
                      snoozeActionTitle: 'Snooze',
                    ),
                    audio: const WarmAlarmAudio(),
                    snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
                  );
                  final result = await WarmAlarm.scheduleAlarm(schedule);
                  setState(() {
                    _lastScheduledAlarmId = result.alarmId;
                    _scheduleWarning = result.warning?.message;
                    _readiness = result.readiness.level.name;
                  });
                } on Exception catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).primaryColor,
                      content: Text('$error'),
                    ),
                  );
                }
              },
              child: const Text('Schedule 1 minute alarm'),
            ),
            const SizedBox(height: 24),
            const Text('Events'),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _events.length,
                itemBuilder: (context, index) => Text(_events[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
