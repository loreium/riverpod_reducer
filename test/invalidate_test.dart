import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pumps the event loop so async dispatches complete.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('invalidate', () {
    test('discards in-flight async events after rebuild', () async {
      final provider = NotifierProvider<_SlowNotifier, int>(_SlowNotifier.new);
      final container = createContainer();
      final notifier = container.read(provider.notifier);

      expect(container.read(provider), 0);

      // Start a slow async dispatch (takes 50ms)
      final future = notifier.dispatch(SetCount(999));

      // Invalidate before it completes — triggers rebuild
      container.invalidate(provider);

      // State should be fresh (0) after rebuild
      expect(container.read(provider), 0);

      // Let the in-flight future complete
      await future;
      await pump();

      // The stale result (999) should NOT have been applied
      expect(container.read(provider), 0);
    });

    test('queued events are discarded on invalidate', () async {
      final provider = NotifierProvider<_SlowNotifier, int>(_SlowNotifier.new);
      final container = createContainer();
      final notifier = container.read(provider.notifier);

      // Dispatch multiple events (they chain on _queue)
      notifier.dispatch(Increment());
      notifier.dispatch(Increment());
      notifier.dispatch(SetCount(42));

      // Invalidate — all should be discarded
      container.invalidate(provider);
      expect(container.read(provider), 0);

      // Let everything settle
      await pump();
      expect(container.read(provider), 0);
    });

    test('refetches external bound state after invalidate', () async {
      final container = createContainer();

      // Initial: externalCountProvider = 10, bound state picks it up
      expect(container.read(boundProvider).externalCount, 10);

      // Dispatch some local changes
      await container
          .read(boundProvider.notifier)
          .dispatch(InternalIncrement());
      expect(container.read(boundProvider).internalCount, 1);

      // Change external provider
      container.read(externalCountProvider.notifier).state = 77;
      await pump();
      expect(container.read(boundProvider).externalCount, 77);

      // Invalidate — should rebuild with current external value (77)
      container.invalidate(boundProvider);
      final state = container.read(boundProvider);
      expect(state.externalCount, 77); // re-bound to current value
      expect(state.internalCount, 0); // reset to initial
    });

    test('new dispatches work after invalidate', () async {
      final provider = NotifierProvider<_SlowNotifier, int>(_SlowNotifier.new);
      final container = createContainer();

      // Dispatch and invalidate
      container.read(provider.notifier).dispatch(SetCount(100));
      container.invalidate(provider);
      expect(container.read(provider), 0);

      // New dispatch on the fresh notifier should work
      await container.read(provider.notifier).dispatch(Increment());
      expect(container.read(provider), 1);
    });
  });
}

/// Notifier with a slow async middleware for testing invalidation.
class _SlowNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  Future<CounterEvent?> middleware(int state, CounterEvent event) async {
    await Future<void>.delayed(Duration(milliseconds: 50));
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
