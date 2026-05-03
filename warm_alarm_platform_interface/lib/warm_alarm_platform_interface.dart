import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:warm_alarm_platform_interface/src/method_channel_warm_alarm.dart';
import 'package:warm_alarm_platform_interface/src/models/models.dart';
export 'package:warm_alarm_platform_interface/src/models/models.dart';

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

  Future<WarmAlarmScheduleResult> scheduleAlarm(WarmAlarmSchedule schedule);

  Future<void> cancelAlarm(int id);

  Future<void> cancelAllAlarms();

  Future<List<WarmAlarmSnapshot>> getScheduledAlarms();

  Stream<WarmAlarmEvent> get events;

  Future<bool> isRinging({int? id});

  Future<void> setKillWarning({required String title, required String body});

  Future<void> clearKillWarning();
}
