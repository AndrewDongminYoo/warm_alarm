import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages, QA-only entrypoint intentionally uses the interface dev dependency.
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveActivityFixtureApp());
}

class LiveActivityFixtureApp extends StatelessWidget {
  const LiveActivityFixtureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.orange),
      home: const LiveActivityFixturePage(),
    );
  }
}

class LiveActivityFixturePage extends StatefulWidget {
  const LiveActivityFixturePage({super.key});

  @override
  State<LiveActivityFixturePage> createState() => _LiveActivityFixturePageState();
}

class _LiveActivityFixturePageState extends State<LiveActivityFixturePage> {
  static const _alarmId = 21001;
  static const _unknownActivityId = 'warm-alarm-unknown-activity';

  final _activityIdController = TextEditingController();

  bool _isRunning = false;
  String _operation = 'None';
  String _resultStatus = 'idle';
  String _resultActivityId = 'None';
  String _submittedState = 'None';

  @override
  void dispose() {
    _activityIdController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final scheduledAt = DateTime.now().add(const Duration(minutes: 10));
    await _run(
      operation: 'Start scheduled',
      submittedState: 'scheduled / ${scheduledAt.toIso8601String()}',
      action: () => WarmAlarmPlatform.instance.startLiveActivity(
        WarmAlarmLiveActivityState(
          alarmId: _alarmId,
          title: 'Warm Alarm QA',
          status: WarmAlarmLiveActivityStatus.scheduled,
          scheduledAt: scheduledAt,
        ),
      ),
      useReturnedId: true,
    );
  }

  Future<void> _updateRinging() async {
    await _update(
      operation: 'Update ringing',
      status: WarmAlarmLiveActivityStatus.ringing,
      title: 'Wake up',
      scheduledAt: null,
    );
  }

  Future<void> _updateSnoozed() async {
    final scheduledAt = DateTime.now().add(const Duration(minutes: 5));
    await _update(
      operation: 'Update snoozed',
      status: WarmAlarmLiveActivityStatus.snoozed,
      title: 'Snoozed alarm',
      scheduledAt: scheduledAt,
    );
  }

  Future<void> _update({
    required String operation,
    required WarmAlarmLiveActivityStatus status,
    required String title,
    required DateTime? scheduledAt,
    String? activityId,
  }) async {
    final requestedId = activityId ?? _activityIdController.text.trim();
    if (requestedId.isEmpty) {
      _showLocalResult(operation: operation, message: 'Enter an ActivityKit ID first.');
      return;
    }
    await _run(
      operation: operation,
      submittedState: '${status.name} / ${scheduledAt?.toIso8601String() ?? 'no time'}',
      action: () => WarmAlarmPlatform.instance.updateLiveActivity(
        requestedId,
        WarmAlarmLiveActivityState(
          alarmId: _alarmId,
          title: title,
          status: status,
          scheduledAt: scheduledAt,
        ),
      ),
    );
  }

  Future<void> _checkUnknownId() async {
    _activityIdController.text = _unknownActivityId;
    await _update(
      operation: 'Check unknown ID',
      status: WarmAlarmLiveActivityStatus.scheduled,
      title: 'Unknown ID check',
      scheduledAt: DateTime.now().add(const Duration(minutes: 10)),
      activityId: _unknownActivityId,
    );
  }

  Future<void> _end() async {
    final activityId = _activityIdController.text.trim();
    if (activityId.isEmpty) {
      _showLocalResult(operation: 'End', message: 'Enter an ActivityKit ID first.');
      return;
    }
    await _run(
      operation: 'End',
      submittedState: 'end request',
      action: () => WarmAlarmPlatform.instance.endLiveActivity(activityId),
    );
  }

  Future<void> _run({
    required String operation,
    required String submittedState,
    required Future<WarmAlarmLiveActivityResult> Function() action,
    bool useReturnedId = false,
  }) async {
    setState(() {
      _isRunning = true;
      _operation = operation;
      _resultStatus = 'pending';
      _submittedState = submittedState;
    });
    try {
      final result = await action();
      if (!mounted) return;
      final resultActivityId = result.activityId;
      setState(() {
        _isRunning = false;
        _resultStatus = result.status.name;
        _resultActivityId = resultActivityId ?? 'None';
        if (useReturnedId && resultActivityId != null) {
          _activityIdController.text = resultActivityId;
        }
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _resultStatus = 'error: $error';
        _resultActivityId = 'None';
      });
    }
  }

  void _showLocalResult({required String operation, required String message}) {
    setState(() {
      _operation = operation;
      _resultStatus = message;
      _resultActivityId = 'None';
      _submittedState = 'None';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Activity QA')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'This fixture controls only the host-configured Live Activity. It does not schedule or ring an alarm.',
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('live_activity_id_field'),
              controller: _activityIdController,
              autocorrect: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'ActivityKit ID',
                helperText: 'Editable so a missing or unknown ID can be exercised.',
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              container: true,
              liveRegion: true,
              label: 'Live Activity operation result',
              value:
                  'Operation $_operation. Status $_resultStatus. Result ID $_resultActivityId. State $_submittedState.',
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Operation: $_operation'),
                      Text('Status: $_resultStatus', key: const Key('live_activity_result_status')),
                      Text('Result ID: $_resultActivityId', key: const Key('live_activity_result_id')),
                      Text('State: $_submittedState'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _FixtureButton(
              key: const Key('live_activity_start'),
              label: 'Start scheduled (+10 min)',
              onPressed: _isRunning ? null : _start,
            ),
            _FixtureButton(
              key: const Key('live_activity_ringing'),
              label: 'Update ringing (no time)',
              onPressed: _isRunning ? null : _updateRinging,
            ),
            _FixtureButton(
              key: const Key('live_activity_snoozed'),
              label: 'Update snoozed (+5 min)',
              onPressed: _isRunning ? null : _updateSnoozed,
            ),
            _FixtureButton(
              key: const Key('live_activity_unknown_id'),
              label: 'Check known-unknown ID',
              onPressed: _isRunning ? null : _checkUnknownId,
            ),
            _FixtureButton(
              key: const Key('live_activity_end'),
              label: 'End entered ID',
              onPressed: _isRunning ? null : _end,
            ),
          ],
        ),
      ),
    );
  }
}

class _FixtureButton extends StatelessWidget {
  const _FixtureButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: label,
        child: FilledButton(onPressed: onPressed, child: Text(label)),
      ),
    );
  }
}
