import 'package:check_readiness/check_readiness.dart';
import 'package:fluttium/fluttium.dart';

export 'src/check_readiness.dart';

/// Will be executed by Fluttium on startup.
void register(Registry registry) {
  registry.registerAction('checkReadiness', CheckReadiness.new);
}
