import 'package:check_readiness/check_readiness.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttium/fluttium.dart';
import 'package:mocktail/mocktail.dart';

class _MockTester extends Mock implements Tester {}

class _MockSemanticsNode extends Mock implements SemanticsNode {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return super.toString();
  }
}

void main() {
  group(CheckReadiness, () {
    late Tester tester;
    late SemanticsNode node;

    setUp(() {
      tester = _MockTester();
      node = _MockSemanticsNode();

      when(() => tester.find(any())).thenAnswer((_) async => node);
    });

    test('executes returns true if node was found', () async {
      const action = CheckReadiness();

      expect(await action.execute(tester), isTrue);
    });

    test('executes returns false if node was not found', () async {
      when(() => tester.find(any())).thenAnswer((_) async => null);

      const action = CheckReadiness();

      expect(await action.execute(tester), isFalse);
    });

    test('show correct description for every platform', () {
      bool isTrue() => true;
      bool isFalse() => false;

      final testCases = [
        (
          'Check alarm inspection state: readiness="blocked", exactScheduling="supported"',
          CheckReadiness(
            isAndroid: isTrue,
            isIOS: isFalse,
            isWeb: isFalse(),
            isWindows: isFalse,
            isLinux: isFalse,
            isMacOS: isFalse,
          ),
        ),
        (
          'Check alarm inspection state: readiness="limited", exactScheduling="limited"',
          CheckReadiness(
            isAndroid: isFalse,
            isIOS: isTrue,
            isWeb: isFalse(),
            isWindows: isFalse,
            isLinux: isFalse,
            isMacOS: isFalse,
          ),
        ),
        (
          'Check alarm inspection state: readiness="unsupported", exactScheduling="unsupported"',
          CheckReadiness(
            isAndroid: isFalse,
            isIOS: isFalse,
            isWeb: isTrue(),
            isWindows: isFalse,
            isLinux: isFalse,
            isMacOS: isFalse,
          ),
        ),
        (
          'Check alarm inspection state: readiness="unsupported", exactScheduling="unsupported"',
          CheckReadiness(
            isAndroid: isFalse,
            isIOS: isFalse,
            isWeb: isFalse(),
            isWindows: isFalse,
            isLinux: isTrue,
            isMacOS: isFalse,
          ),
        ),
        (
          'Check alarm inspection state: readiness="limited", exactScheduling="unsupported"',
          CheckReadiness(
            isAndroid: isFalse,
            isIOS: isFalse,
            isWeb: isFalse(),
            isWindows: isFalse,
            isLinux: isFalse,
            isMacOS: isTrue,
          ),
        ),
        (
          'Check alarm inspection state: readiness="unsupported", exactScheduling="unsupported"',
          CheckReadiness(
            isAndroid: isFalse,
            isIOS: isFalse,
            isWeb: isFalse(),
            isWindows: isTrue,
            isLinux: isFalse,
            isMacOS: isFalse,
          ),
        ),
      ];

      for (final testCase in testCases) {
        expect(
          testCase.$2.description(),
          equals(testCase.$1),
        );
      }
    });

    test('throws UnsupportedError on unknown platform', () {
      final action = CheckReadiness(
        isAndroid: () => false,
        isIOS: () => false,
        isWeb: false,
        isWindows: () => false,
        isLinux: () => false,
        isMacOS: () => false,
      );

      expect(action.description, throwsUnsupportedError);
    });
  });
}
