import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('applyEvent() middleware', () {
    test('logs all events in order', () async {
      final container = createContainer();
      final notifier = container.read(loggingProvider.notifier);

      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      await notifier.dispatch(SetCount(10));
      await notifier.dispatch(Decrement());

      expect(notifier.eventLog, hasLength(4));
      expect(notifier.eventLog[0], isA<Increment>());
      expect(notifier.eventLog[1], isA<Increment>());
      expect(notifier.eventLog[2], isA<SetCount>());
      expect(notifier.eventLog[3], isA<Decrement>());
    });

    test('state still updates correctly through middleware', () async {
      final container = createContainer();
      final notifier = container.read(loggingProvider.notifier);

      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      expect(container.read(loggingProvider), 3);
    });

    test('middleware can block events by returning same state', () async {
      final container = createContainer();
      final provider = NotifierProvider<_BlockingNotifier, int>(
        _BlockingNotifier.new,
      );
      final notifier = container.read(provider.notifier);

      await notifier.dispatch(Increment());
      expect(container.read(provider), 1);

      // Decrement is blocked by middleware
      await notifier.dispatch(Decrement());
      expect(container.read(provider), 1); // unchanged
    });
  });
}

/// Middleware that blocks Decrement events.
class _BlockingNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  Future<CounterEvent?> middleware(int state, CounterEvent event) async {
    if (event is Decrement) return null; // block
    return event;
  }

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}
