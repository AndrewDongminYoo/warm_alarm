import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';
import 'package:warm_alarm_platform_interface/src/models/models.dart';
export 'package:warm_alarm_platform_interface/src/models/models.dart';

const _unsupportedRemediationResult = WarmAlarmRemediationResult(
  status: WarmAlarmRemediationStatus.unsupported,
  permissionState: WarmAlarmPermissionState(
    notificationsGranted: false,
    exactAlarmGranted: false,
    fullScreenIntentGranted: false,
  ),
  readiness: WarmAlarmReadiness(
    level: WarmAlarmReadinessLevel.unsupported,
    reasons: <WarmAlarmReadinessReason>[
      WarmAlarmReadinessReason.platformUnsupported,
    ],
  ),
);

/// {@template warm_alarm_platform}
/// The interface that implementations of
/// warm_alarm must implement.
///
/// Platform implementations should extend this class
/// rather than implement it as `WarmAlarm`.
///
/// Extending this class (using `extends`) ensures that the subclass will get
/// the default implementation, while platform implementations that `implements`
/// this interface will be broken by newly added
/// [WarmAlarmPlatform] methods.
/// {@endtemplate}
abstract class WarmAlarmPlatform extends PlatformInterface {
  /// {@macro warm_alarm_platform}
  WarmAlarmPlatform() : super(token: _token);

  static final Object _token = Object();

  static WarmAlarmPlatform _instance = MethodChannelWarmAlarm();

  /// The default instance of [WarmAlarmPlatform] to use.
  ///
  /// Defaults to [MethodChannelWarmAlarm].
  static WarmAlarmPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [WarmAlarmPlatform]
  /// when they register themselves.
  static set instance(WarmAlarmPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<void> init();

  Future<WarmAlarmCapabilities> getCapabilities();

  Future<WarmAlarmPermissionState> getPermissionState();

  Future<WarmAlarmReadiness> getReadiness();

  /// Requests notification authorization where the platform supports it.
  /// The result includes the permission state and readiness snapshot when the action returns.
  Future<WarmAlarmRemediationResult> requestNotificationPermission() async => _unsupportedRemediationResult;

  /// Opens native settings for a readiness [reason] when the platform supports it.
  /// Settings open in a separate screen and this call returns as soon as the platform accepts
  /// the request, so the returned snapshot still describes the state before the user changed
  /// anything. Call [getReadiness] again once the app resumes to see the outcome.
  Future<WarmAlarmRemediationResult> openReadinessSettings(
    WarmAlarmReadinessReason reason,
  ) async => _unsupportedRemediationResult;

  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule);

  Future<void> cancelAlarm(int id);

  Future<void> cancelAllAlarms();

  Future<List<WarmAlarmSnapshot>> getScheduledAlarms();

  Stream<WarmAlarmEvent> get events;

  Future<bool> isRinging({int? id});

  Future<void> setKillWarning({required String title, required String body});

  Future<void> clearKillWarning();
}
