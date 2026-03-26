import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('reduce() purity', () {
    late CounterNotifier notifier;

    setUp(() {
      notifier = CounterNotifier();
    });

    test('Increment adds 1', () {
      expect(notifier.reduce(0, Increment()), 1);
      expect(notifier.reduce(5, Increment()), 6);
      expect(notifier.reduce(-1, Increment()), 0);
    });

    test('Decrement subtracts 1', () {
      expect(notifier.reduce(0, Decrement()), -1);
      expect(notifier.reduce(5, Decrement()), 4);
    });

    test('SetCount sets exact value', () {
      expect(notifier.reduce(0, SetCount(42)), 42);
      expect(notifier.reduce(100, SetCount(0)), 0);
    });

    test('Reset returns to 0', () {
      expect(notifier.reduce(99, Reset()), 0);
      expect(notifier.reduce(0, Reset()), 0);
    });

    test('same input always produces same output', () {
      final result1 = notifier.reduce(5, Increment());
      final result2 = notifier.reduce(5, Increment());
      expect(result1, result2);
    });

    test('sequential events compose correctly', () {
      var state = 0;
      state = notifier.reduce(state, Increment());
      state = notifier.reduce(state, Increment());
      state = notifier.reduce(state, Decrement());
      state = notifier.reduce(state, SetCount(10));
      state = notifier.reduce(state, Increment());
      expect(state, 11);
    });
  });
}
