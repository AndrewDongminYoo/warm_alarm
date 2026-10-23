import 'dart:async';

import 'package:flutter/material.dart';
import 'package:warm_alarm/warm_alarm.dart';
import 'package:warm_alarm_example/voice_audio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

WarmAlarmReadinessReason? readinessRemediationReason(WarmAlarmReadiness readiness) {
  final reasons = readiness.reasons;
  if (reasons.isEmpty) return null;

  final settings = readiness.notificationSettings;
  if (settings == null) return reasons.first;

  final authorizationNeedsAttention =
      settings.authorizationStatus != WarmAlarmNotificationAuthorizationStatus.authorized;
  final deliveryNeedsAttention =
      !settings.alertsEnabled || !settings.soundsEnabled || settings.timeSensitiveEnabled == false;
  if ((authorizationNeedsAttention || deliveryNeedsAttention) &&
      reasons.contains(WarmAlarmReadinessReason.notificationPermissionDenied)) {
    return WarmAlarmReadinessReason.notificationPermissionDenied;
  }
  if ((authorizationNeedsAttention || deliveryNeedsAttention) &&
      reasons.contains(WarmAlarmReadinessReason.backgroundExecutionLimited)) {
    return WarmAlarmReadinessReason.backgroundExecutionLimited;
  }

  for (final reason in reasons) {
    if (reason != WarmAlarmReadinessReason.backgroundExecutionLimited) return reason;
  }
  return null;
}

class MyApp extends StatelessWidget {
  const new({this.audio, super.key});

  final VoiceAudio? audio;

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB34F32),
      brightness: brightness,
      surface: dark ? const Color(0xFF241E1A) : const Color(0xFFFFFCF8),
    );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: dark ? const Color(0xFF181411) : const Color(0xFFF4EFE7),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.4),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WarmAlarm',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: HomePage(audio: audio),
  );
}

class HomePage extends StatefulWidget {
  const new({this.audio, super.key});

  final VoiceAudio? audio;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final VoiceAudio _audio;
  VoiceClip? _clip;
  bool _recording = false;
  bool _playing = false;
  bool _useVoice = false;
  bool _busy = false;
  bool _loading = true;
  bool _detailsExpanded = false;
  final GlobalKey _errorKey = GlobalKey();
  bool _wakeCheck = true;
  bool _alarmActive = false;
  Duration _delay = const Duration(minutes: 1);
  Duration _elapsed = Duration.zero;
  final Stopwatch _recordingClock = Stopwatch();
  Timer? _recordingTimer;
  WarmAlarmReadiness? _readiness;
  WarmAlarmCapabilities? _capabilities;
  String? _remediationStatus;
  String? _errorTitle;
  String? _errorMessage;
  int? _lastScheduledAlarmId;
  DateTime? _scheduledAt;
  List<WarmAlarmWarning> _warnings = const [];
  final List<WarmAlarmEvent> _events = [];
  StreamSubscription<WarmAlarmEvent>? _eventsSubscription;

  @override
  void initState() {
    super.initState();
    _audio = widget.audio ?? VoiceAudio();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadRecording());
    _eventsSubscription = WarmAlarm.events.listen((event) {
      if (!mounted) return;
      setState(() {
        _events.insert(0, event);
        if (_events.length > 20) _events.removeLast();
        if (event.alarmId == _lastScheduledAlarmId && event is WarmAlarmStopped) _alarmActive = false;
      });
    });
  }

  Future<void> _loadRecording() async {
    try {
      final clip = await _audio.load();
      if (mounted) {
        setState(() {
          _clip = clip;
          _useVoice = clip != null;
        });
      }
    } on Exception catch (error, stack) {
      _showError('Could not load your recording', 'Try recording a new message.', error, stack);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _recordingClock.stop();
    unawaited(_eventsSubscription?.cancel());
    unawaited(
      _audio.dispose().catchError((Object error, StackTrace stack) {
        debugPrint('Could not release audio resources: $error');
        debugPrintStack(stackTrace: stack);
      }),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _recording && !_busy) unawaited(_finishRecording());
    if (state == AppLifecycleState.resumed && _readiness != null && !_busy && !_recording) {
      unawaited(_refreshInspection());
    }
  }

  void _showError(String title, String message, Object error, StackTrace stack) {
    debugPrint('$title: $error');
    debugPrintStack(stackTrace: stack);
    if (!mounted) return;
    setState(() {
      _errorTitle = title;
      _errorMessage = message;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _errorKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250));
      }
    });
  }

  Future<void> _perform(String title, String message, Future<void> Function() action) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _errorTitle = null;
      _errorMessage = null;
    });
    try {
      await action();
    } on Exception catch (error, stack) {
      _showError(title, message, error, stack);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshInspection() => _perform(
    'Could not inspect alarm readiness',
    'Try inspecting again before scheduling an alarm.',
    () async {
      final readiness = await WarmAlarm.getReadiness();
      final capabilities = await WarmAlarm.getCapabilities();
      if (mounted) {
        setState(() {
          _readiness = readiness;
          _capabilities = capabilities;
          _detailsExpanded = true;
        });
      }
    },
  );

  Future<void> _remediate({bool openSettings = false}) => _perform(
    openSettings ? 'Could not open notification settings' : 'Could not request notification permission',
    'Check notification settings in System Settings, then inspect again.',
    () async {
      final reason = _readiness == null ? null : readinessRemediationReason(_readiness!);
      if (openSettings && reason == null) {
        setState(() => _remediationStatus = 'no readiness reason to fix');
        return;
      }
      final result = openSettings
          ? await WarmAlarm.openReadinessSettings(reason!)
          : await WarmAlarm.requestNotificationPermission();
      if (mounted) {
        setState(() {
          _remediationStatus = result.status.name;
          _readiness = result.readiness;
        });
      }
    },
  );

  Future<void> _startRecording() => _perform(
    'Could not start recording',
    'Check microphone access in system settings and try again.',
    () async {
      await _audio.stopPreview();
      await _audio.startRecording();
      if (!mounted) {
        await _audio.dispose();
        return;
      }
      _recordingClock
        ..reset()
        ..start();
      setState(() {
        _recording = true;
        _playing = false;
        _elapsed = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _elapsed = _recordingClock.elapsed);
        if (_elapsed >= const Duration(seconds: 15) && !_busy) unawaited(_finishRecording());
      });
    },
  );

  Future<void> _finishRecording() => _perform(
    'Could not save recording',
    'Try recording another message before scheduling.',
    () async {
      _recordingTimer?.cancel();
      _recordingClock.stop();
      try {
        final clip = await _audio.stopRecording(_recordingClock.elapsed);
        if (mounted) {
          setState(() {
            _clip = clip;
            _useVoice = true;
          });
        }
      } finally {
        if (mounted) setState(() => _recording = _audio.isRecording);
      }
    },
  );

  Future<void> _preview() => _perform(
    'Could not play recording',
    'Try recording a new message.',
    () async {
      if (_playing) {
        await _audio.stopPreview();
        if (mounted) setState(() => _playing = false);
      } else {
        await _audio.preview(
          _clip!.path,
          onComplete: () {
            if (mounted) setState(() => _playing = false);
          },
          onError: (error, stack) {
            if (mounted) setState(() => _playing = false);
            _showError('Could not play recording', 'Try recording a new message.', error, stack);
          },
        );
        if (mounted) setState(() => _playing = true);
      }
    },
  );

  Future<void> _schedule() => _perform(
    'Could not schedule alarm',
    'Inspect readiness and check permissions, then try again.',
    () async {
      await _audio.stopPreview();
      if (mounted) setState(() => _playing = false);
      final voicePath = _useVoice ? _clip?.path : null;
      final systemSound = voicePath == null ? null : await WarmAlarm.prepareSystemSound(primaryFilePath: voicePath);
      final at = DateTime.now().add(_delay);
      final result = await WarmAlarm.scheduleAlarm(
        WarmAlarmSchedule(
          id: 42,
          scheduledAt: at,
          notification: WarmAlarmNotification(
            title: 'Warm Alarm',
            body: voicePath == null ? 'Your demo alarm is ready.' : 'A message from you is ready.',
            stopActionTitle: 'Stop',
            snoozeActionTitle: 'Snooze',
          ),
          audio: WarmAlarmAudio(
            filePath: voicePath,
            assetPath: voicePath == null ? 'assets/audio/alarm_ring.wav' : null,
            systemSoundFilePath: systemSound,
            loop: false,
          ),
          snooze: const WarmAlarmSnooze(duration: Duration(minutes: 5)),
          wakeCheck: _wakeCheck
              ? const WarmAlarmWakeCheck(
                  checkDelay: Duration(minutes: 2),
                  retriggerDelay: Duration(minutes: 1),
                )
              : null,
        ),
      );
      if (!mounted) return;
      setState(() {
        _lastScheduledAlarmId = result.alarmId;
        _scheduledAt = at;
        _warnings = result.warnings;
        _readiness = result.readiness;
        _alarmActive = true;
      });
    },
  );

  Future<void> _cancel() => _perform(
    'Could not cancel alarm',
    'Try canceling again before scheduling another alarm.',
    () async {
      await WarmAlarm.cancelAlarm(42);
      if (mounted) setState(() => _alarmActive = false);
    },
  );

  String _duration(Duration value) => '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            if (viewport.maxWidth >= 1100 &&
                viewport.maxHeight >= 640 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
              return _desktopDashboard();
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(Icons.alarm_rounded, size: 32, color: colors.primary),
                          Text('WarmAlarm', style: text.titleLarge),
                          const _Pill(label: 'VOICE DEMO'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Your voice, your alarm.', style: text.headlineMedium),
                      const SizedBox(height: 8),
                      Text('Record a message. Hear it when your alarm rings.', style: text.bodyLarge),
                      const SizedBox(height: 16),
                      if (_errorTitle != null) ...[
                        _errorPanel(),
                        const SizedBox(height: 16),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final voice = _voicePanel();
                          final alarm = _alarmPanel();
                          if (constraints.maxWidth >= 620 && MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: voice),
                                const SizedBox(width: 16),
                                Expanded(child: alarm),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              voice,
                              const SizedBox(height: 16),
                              alarm,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _readinessPanel(),
                      const SizedBox(height: 20),
                      _eventsPanel(),
                      const SizedBox(height: 24),
                      Text(
                        'Built with warm_alarm · Recordings saved in this app.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _desktopDashboard() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.alarm_rounded, size: 32, color: colors.primary),
              const SizedBox(width: 12),
              Text('WarmAlarm', style: text.titleLarge),
              const SizedBox(width: 12),
              const _Pill(label: 'VOICE DEMO'),
              const Spacer(),
              Text('Your voice, your alarm.', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _voicePanel(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorTitle != null) ...[_errorPanel(), const SizedBox(height: 12)],
                              _eventsPanel(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _alarmPanel(dashboard: true)),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: _readinessPanel(dashboard: true))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Built with warm_alarm · Recordings saved in this app.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _errorPanel() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      key: _errorKey,
      liveRegion: true,
      child: _Panel(
        tint: colors.errorContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: colors.onErrorContainer),
                const Spacer(),
                IconButton(
                  tooltip: 'Dismiss error',
                  onPressed: () => setState(() {
                    _errorTitle = null;
                    _errorMessage = null;
                  }),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(_errorTitle!, style: text.titleMedium?.copyWith(color: colors.onErrorContainer)),
            const SizedBox(height: 4),
            Text(_errorMessage!, style: TextStyle(color: colors.onErrorContainer)),
          ],
        ),
      ),
    );
  }

  Widget _readinessPanel({bool dashboard = false}) {
    final colors = Theme.of(context).colorScheme;
    final canAct = !_loading && !_busy && !_recording;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: dashboard ? 8 : 12,
            runSpacing: dashboard ? 8 : 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(
                label: _readiness == null ? 'Not inspected' : 'Readiness: ${_readiness!.level.name}',
                color: _readiness?.level == WarmAlarmReadinessLevel.ready
                    ? colors.tertiaryContainer
                    : colors.secondaryContainer,
              ),
              ElevatedButton.icon(
                onPressed: canAct ? _refreshInspection : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Inspect Alarm API'),
              ),
              if (!dashboard)
                TextButton.icon(
                  onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
                  icon: Icon(_detailsExpanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(_detailsExpanded ? 'Hide platform details' : 'Show platform details'),
                ),
            ],
          ),
          if (dashboard || _detailsExpanded) ...[
            SizedBox(height: dashboard ? 8 : 12),
            if (!dashboard)
              const Text('A snapshot of current permissions and limits. Future delivery is not guaranteed.'),
            if (_readiness != null) ...[
              SizedBox(height: dashboard ? 8 : 12),
              Text(
                'Readiness reasons: ${_readiness!.reasons.isEmpty ? 'none' : _readiness!.reasons.map((r) => r.name).join(', ')}',
              ),
            ],
            SizedBox(height: dashboard ? 8 : 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: canAct ? _remediate : null,
                  child: const Text('Request notification permission'),
                ),
                OutlinedButton(
                  onPressed: canAct ? () => _remediate(openSettings: true) : null,
                  child: const Text('Open readiness settings'),
                ),
              ],
            ),
            if (_remediationStatus != null) ...[
              SizedBox(height: dashboard ? 8 : 12),
              Text('Remediation: $_remediationStatus'),
              const Text('Inspect again after changing system settings.'),
            ],
            if (_capabilities case final capabilities?) ...[
              Divider(height: dashboard ? 16 : 32),
              _eyebrow('FEATURE SUPPORT'),
              SizedBox(height: dashboard ? 8 : 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 && MediaQuery.textScalerOf(context).scale(1) <= 1.3
                      ? 3
                      : 1;
                  final values = <(String, WarmAlarmSupportStatus)>[
                    ('Exact scheduling', capabilities.exactScheduling),
                    ('Notification scheduling', capabilities.notificationScheduling),
                    ('Background audio', capabilities.backgroundAudioPlayback),
                    ('Full-screen presentation', capabilities.fullScreenPresentation),
                    ('Wake-check', capabilities.wakeCheck),
                    ('Live Activity', capabilities.liveActivity),
                  ];
                  return Wrap(
                    spacing: dashboard ? 0 : 12,
                    runSpacing: dashboard ? 0 : 12,
                    children: [
                      for (final (label, support) in values)
                        SizedBox(
                          width: (constraints.maxWidth - (columns - 1) * 12) / columns,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: dashboard ? const EdgeInsets.symmetric(horizontal: 8) : const EdgeInsets.all(12),
                              child: Text('$label: ${support.name}'),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _eyebrow(String label) => Text(
    label,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _voicePanel() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow('01 / MAKE IT PERSONAL'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _recording ? colors.errorContainer : colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _recording ? Icons.mic : Icons.graphic_eq_rounded,
                size: 28,
                color: _recording ? colors.onErrorContainer : colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _recording
                ? 'Make it a good morning.'
                : _clip == null
                ? 'A message from you.'
                : 'Your voice is ready.',
            style: text.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            _recording
                ? 'Recording ${_duration(_elapsed)} / 0:15'
                : _clip == null
                ? 'Say something you would like to wake up to. Up to 15 seconds, saved on this device.'
                : 'Saved recording · ${_duration(_clip!.duration)}. Preview it before scheduling.',
          ),
          if (_recording) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: (_elapsed.inMilliseconds / 15000).clamp(0, 1), minHeight: 4),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loading || _busy || _alarmActive
                ? null
                : _recording
                ? _finishRecording
                : _startRecording,
            icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded),
            label: Text(
              _recording
                  ? 'Save recording'
                  : _clip == null
                  ? 'Record my voice'
                  : 'Record again',
            ),
          ),
          if (_clip != null && !_recording) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loading || _busy || _alarmActive ? null : _preview,
              icon: Icon(_playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
              label: Text(_playing ? 'Stop preview' : 'Preview voice'),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _alarmActive
                ? 'Cancel the pending alarm before recording or previewing.'
                : 'Microphone access is requested only when you record.',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _alarmPanel({bool dashboard = false}) {
    final text = Theme.of(context).textTheme;
    final canAct = !_loading && !_busy && !_recording;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow('02 / SET YOUR ALARM'),
          const SizedBox(height: 16),
          Text('Something to wake up to.', style: text.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Demo chime'),
                selected: !_useVoice,
                onSelected: canAct ? (_) => setState(() => _useVoice = false) : null,
              ),
              if (_clip != null)
                ChoiceChip(
                  label: const Text('My voice'),
                  selected: _useVoice,
                  onSelected: canAct ? (_) => setState(() => _useVoice = true) : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<Duration>(
            initialValue: _delay,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ring in', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: Duration(seconds: 15), child: Text('15 seconds')),
              DropdownMenuItem(value: Duration(minutes: 1), child: Text('1 minute')),
            ],
            onChanged: canAct ? (value) => setState(() => _delay = value!) : null,
          ),
          const SizedBox(height: 12),
          Tooltip(
            message: 'Request a follow-up check. Unsupported platforms report a warning.',
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Wake-check'),
              value: _wakeCheck,
              onChanged: canAct ? (value) => setState(() => _wakeCheck = value) : null,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: canAct ? _schedule : null,
            icon: const Icon(Icons.alarm_add_rounded),
            label: Text(_delay.inSeconds == 60 ? 'Schedule 1 minute alarm' : 'Schedule 15 second alarm'),
          ),
          if (_alarmActive)
            TextButton.icon(
              onPressed: canAct ? _cancel : null,
              icon: const Icon(Icons.alarm_off_rounded),
              label: const Text('Cancel alarm'),
            ),
          if (_lastScheduledAlarmId != null) ...[
            Divider(height: dashboard ? 12 : 32),
            if (dashboard)
              Expanded(child: SingleChildScrollView(child: _scheduleResult(dashboard: true)))
            else
              _scheduleResult(),
          ],
        ],
      ),
    );
  }

  Widget _scheduleResult({bool dashboard = false}) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_alarmActive ? 'Alarm request accepted' : 'Alarm canceled or stopped', style: text.titleMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            children: [
              Text('Scheduled alarm id: $_lastScheduledAlarmId'),
              if (_scheduledAt != null) Text('Scheduled for ${TimeOfDay.fromDateTime(_scheduledAt!).format(context)}'),
            ],
          ),
          SizedBox(height: dashboard ? 8 : 12),
          if (_warnings.isEmpty) ...[
            if (!dashboard) ...[const _Pill(label: 'No warnings reported'), const SizedBox(height: 8)],
            const Text('Schedule warning code: none'),
            const Text('Schedule warning: none'),
          ] else ...[
            for (final warning in _warnings)
              Padding(
                padding: EdgeInsets.only(bottom: dashboard ? 0 : 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(dashboard ? 8 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!dashboard) ...[const Icon(Icons.info_outline_rounded), const SizedBox(height: 8)],
                        Text(
                          'Schedule warning code: ${warning.code?.name ?? 'unclassified'}',
                          style: text.titleSmall,
                        ),
                        SizedBox(height: dashboard ? 4 : 8),
                        Text('Schedule warning: ${warning.message}'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          const Text('Acceptance does not guarantee future delivery.'),
        ],
      ),
    );
  }

  Widget _eventsPanel() {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('LIVE EVENT LOG'),
          const SizedBox(height: 8),
          Text('Events', style: text.titleLarge),
          const SizedBox(height: 16),
          if (_events.isEmpty) const Text('No events yet. Schedule an alarm to see what happens next.'),
          for (final event in _events)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(switch (event) {
                    WarmAlarmFired() => Icons.notifications_active_outlined,
                    WarmAlarmStopped() => Icons.check_circle_outline,
                    WarmAlarmFailed() => Icons.error_outline,
                    _ => Icons.schedule,
                  }, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${event.runtimeType} #${event.alarmId}', style: text.titleSmall),
                        Text(TimeOfDay.fromDateTime(event.occurredAt.toLocal()).format(context), style: text.bodySmall),
                        if (event case WarmAlarmFailed(:final failure)) Text(failure.message ?? failure.code.name),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const new({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Material(
    color: tint ?? Theme.of(context).colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5)),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _Pill extends StatelessWidget {
  const new({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );
}
