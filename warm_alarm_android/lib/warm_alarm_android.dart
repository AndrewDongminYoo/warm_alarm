import 'package:flutter/foundation.dart';
import 'package:warm_alarm_android/src/messages.g.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// {@template warm_alarm_android}
/// The Android implementation of [WarmAlarmPlatform].
/// {@endtemplate}
class WarmAlarmAndroid extends WarmAlarmPlatform {
  /// {@macro warm_alarm_android}
  WarmAlarmAndroid({
    @visibleForTesting WarmAlarmApi? api,
  }) : api = api ?? WarmAlarmApi();

  /// The API used to interact with the native platform.
  final WarmAlarmApi api;

  /// Registers this class as the default instance of
  /// [WarmAlarmPlatform].
  static void registerWith() {
    WarmAlarmPlatform.instance =
        WarmAlarmAndroid();
  }

  @override
  Future<String?> getPlatformName() {
    return api.getPlatformName();
  }
}
