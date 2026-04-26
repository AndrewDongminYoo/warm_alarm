// WarmAlarmApi must be abstract.
// ignore_for_file: one_member_abstracts

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'warm_alarm',
    swiftOut: 'ios/warm_alarm_ios/Sources/warm_alarm_ios/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
@HostApi()
abstract class WarmAlarmApi {
  @async
  String? getPlatformName();
}
