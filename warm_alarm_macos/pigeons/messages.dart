// WarmAlarmApi must be abstract.
// ignore_for_file: one_member_abstracts

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'warm_alarm',
    swiftOut:
        'macos/warm_alarm_macos/Sources/warm_alarm_macos/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
@HostApi()
abstract class WarmAlarmApi {
  @async
  String? getPlatformName();
}
