import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:warm_alarm_platform_interface/warm_alarm_platform_interface.dart';

/// An implementation of [WarmAlarmPlatform]
/// that uses method channels.
class MethodChannelWarmAlarm
    extends WarmAlarmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('warm_alarm');

  @override
  Future<String?> getPlatformName() {
    return methodChannel.invokeMethod<String>('getPlatformName');
  }
}
