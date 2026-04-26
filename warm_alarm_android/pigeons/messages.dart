// WarmAlarmApi must be abstract.
// ignore_for_file: one_member_abstracts

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'warm_alarm',
    kotlinOut: 'android/src/main/kotlin/com/andrew/alarm/Messages.g.kt',
    kotlinOptions: KotlinOptions(),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
@HostApi()
abstract class WarmAlarmApi {
  @async
  String? getPlatformName();
}
