import 'package:flutter/foundation.dart';
import 'package:warm_alarm_ios/src/messages.g.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// {@template warm_alarm_ios}
/// The iOS implementation of [WarmAlarmPlatform].
/// {@endtemplate}
class WarmAlarmIOS extends WarmAlarmPlatform {
  /// {@macro warm_alarm_ios}
  WarmAlarmIOS({
    @visibleForTesting WarmAlarmApi? api,
  }) : api = api ?? WarmAlarmApi();

  /// The API used to interact with the native platform.
  final WarmAlarmApi api;

  /// Registers this class as the default instance of
  /// [WarmAlarmPlatform].
  static void registerWith() {
    WarmAlarmPlatform.instance =
        WarmAlarmIOS();
  }

  @override
  Future<String?> getPlatformName() {
    return api.getPlatformName();
  }
}
