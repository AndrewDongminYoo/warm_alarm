import 'package:check_readiness/check_readiness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttium/fluttium.dart';
import 'package:mocktail/mocktail.dart';

class _MockRegister extends Mock implements Registry {}

void main() {
  test('can be registered', () {
    final registry = _MockRegister();
    when(
      () => registry.registerAction(
        any(),
        any(),
        shortHandIs: any(named: 'shortHandIs'),
      ),
    ).thenAnswer((_) {});

    register(registry);

    verify(
      () => registry.registerAction(
        any(that: equals('checkReadiness')),
        any(that: equals(CheckReadiness.new)),
        shortHandIs: any(named: 'shortHandIs', that: isNull),
      ),
    ).called(1);
  });
}
