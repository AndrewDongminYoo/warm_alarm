import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:fluttium/fluttium.dart';

/// {@template check_readiness}
/// An action that checks the example alarm inspection state.
///
/// Usage:
///
/// ```yaml
/// - checkReadiness:
/// ```
/// {@endtemplate}
class CheckReadiness extends Action {
  /// {@macro check_readiness}
  const new({
    @visibleForTesting this._isAndroid = _platformIsAndroid,
    @visibleForTesting this._isIOS = _platformIsIOS,
    @visibleForTesting this._isLinux = _platformIsLinux,
    @visibleForTesting this._isMacOS = _platformIsMacOS,
    @visibleForTesting this._isWindows = _platformIsWindows,
    @visibleForTesting this._isWeb = kIsWeb,
  });

  static const _readinessPattern = '(ready|limited|blocked|unsupported)';

  final bool _isWeb;

  final bool Function() _isAndroid;

  final bool Function() _isIOS;

  final bool Function() _isLinux;

  final bool Function() _isMacOS;

  final bool Function() _isWindows;

  String get _expectedExactScheduling {
    if (_isAndroid()) return 'supported';
    if (_isIOS()) return '(limited|supported)';
    if (_isMacOS()) return 'unsupported';
    if (_isWeb || _isLinux() || _isWindows()) return 'unsupported';
    throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
  }

  @override
  Future<bool> execute(Tester tester) async {
    final readinessVisible = await const ExpectVisible(
      text: 'Readiness: $_readinessPattern',
    ).execute(tester);
    final exactSchedulingVisible = await ExpectVisible(
      text: 'Exact scheduling: $_expectedExactScheduling',
    ).execute(tester);

    return readinessVisible && exactSchedulingVisible;
  }

  @override
  String description() =>
      'Check alarm inspection state: readiness="$_readinessPattern", exactScheduling="$_expectedExactScheduling"';
}

// coverage:ignore-start these are just wrappers for overloading
bool _platformIsAndroid() => Platform.isAndroid;
bool _platformIsIOS() => Platform.isIOS;
bool _platformIsLinux() => Platform.isLinux;
bool _platformIsMacOS() => Platform.isMacOS;
bool _platformIsWindows() => Platform.isWindows;
// coverage:ignore-end
