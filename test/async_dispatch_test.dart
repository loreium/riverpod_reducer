import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('async applyEvent', () {
    test('updates state after await', () async {
      final container = createContainer();
      final notifier = container.read(asyncCounterProvider.notifier);

      expect(container.read(asyncCounterProvider), 0);
      await notifier.dispatch(Increment());
      expect(container.read(asyncCounterProvider), 1);
    });

    test('sequential event ordering', () async {
      final container = createContainer();
      final notifier = container.read(asyncCounterProvider.notifier);

      // Dispatch multiple events without awaiting individually
      final f1 = notifier.dispatch(Increment());
      final f2 = notifier.dispatch(Increment());
      final f3 = notifier.dispatch(SetCount(10));
      final f4 = notifier.dispatch(Decrement());

      await Future.wait([f1, f2, f3, f4].whereType<Future>());
      expect(container.read(asyncCounterProvider), 9);
      expect(notifier.eventLog, hasLength(4));
      expect(notifier.eventLog[0], isA<Increment>());
      expect(notifier.eventLog[1], isA<Increment>());
      expect(notifier.eventLog[2], isA<SetCount>());
      expect(notifier.eventLog[3], isA<Decrement>());
    });

    test('intermediate state emission via this.state', () async {
      final provider = NotifierProvider<_IntermediateNotifier, int>(
        _IntermediateNotifier.new,
      );
      final container = createContainer();
      final notifier = container.read(provider.notifier);
      final states = <int>[];

      container.listen(provider, (_, next) => states.add(next));

      await notifier.dispatch(SetCount(42));

      // Should have seen intermediate state (-1) then final state (42)
      expect(states, [
        -1, // intermediate
        42, // final
      ]);
    });

    test(
      'error in async applyEvent does not break subsequent events',
      () async {
        final provider = NotifierProvider<_ErrorNotifier, int>(
          _ErrorNotifier.new,
        );
        final container = createContainer();
        final notifier = container.read(provider.notifier);

        // First dispatch will throw
        final f1 = notifier.dispatch(SetCount(-1));
        // Second dispatch should still work
        final f2 = notifier.dispatch(Increment());

        // The erroring dispatch should throw
        await expectLater(f1, throwsA(isA<Exception>()));
        await f2;

        // State should reflect the successful increment from 0
        expect(container.read(provider), 1);
      },
    );

    test('mixed sync and async events in same notifier', () async {
      final provider = NotifierProvider<_MixedNotifier, int>(
        _MixedNotifier.new,
      );
      final container = createContainer();
      final notifier = container.read(provider.notifier);

      await notifier.dispatch(Increment());
      expect(container.read(provider), 1);

      await notifier.dispatch(SetCount(10)); // has extra delay
      expect(container.read(provider), 10);

      await notifier.dispatch(Increment());
      expect(container.read(provider), 11);
    });

    test(
      'slower earlier events do not reorder with faster later events',
      () async {
        final provider = NotifierProvider<_VaryingDelayNotifier, List<String>>(
          _VaryingDelayNotifier.new,
        );
        final container = createContainer();
        final notifier = container.read(provider.notifier);

        // Event A takes 100ms, event B takes 10ms, event C takes 50ms.
        // Without sequential queuing, B would finish before A.
        final fA = notifier.dispatch(_Append('A')); // slow
        final fB = notifier.dispatch(_Append('B')); // fast
        final fC = notifier.dispatch(_Append('C')); // medium

        await Future.wait([fA, fB, fC]);
        expect(container.read(provider), ['A', 'B', 'C']);
      },
    );

    test('dispatch always returns Future', () async {
      final container = createContainer();
      final notifier = container.read(counterProvider.notifier);

      final result = notifier.dispatch(Increment());
      expect(result, isA<Future>());
      await result;
      expect(container.read(counterProvider), 1);
    });
  });
}

// --- Events for _VaryingDelayNotifier ---

sealed class _ListEvent {}

class _Append extends _ListEvent {
  _Append(this.value);
  final String value;
}

/// Notifier where each appended value has a different delay,
/// verifying that the queue processes events in dispatch order.
class _VaryingDelayNotifier extends ReducerNotifier<List<String>, _ListEvent> {
  static const _delays = {'A': 100, 'B': 10, 'C': 50};

  @override
  List<String> initialState() => [];

  @override
  Future<List<String>> applyEvent(List<String> state, _ListEvent event) async {
    if (event is _Append) {
      await Future<void>.delayed(
        Duration(milliseconds: _delays[event.value] ?? 0),
      );
    }
    return reduce(state, event);
  }

  @override
  List<String> reduce(List<String> state, _ListEvent event) => switch (event) {
    _Append(:final value) => [...state, value],
  };
}

/// Notifier that emits intermediate state during async applyEvent.
class _IntermediateNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  Future<int> applyEvent(int state, CounterEvent event) async {
    if (event is SetCount) {
      this.state = -1; // intermediate state
      await Future<void>.delayed(Duration(milliseconds: 10));
      return event.value; // final state
    }
    return reduce(state, event);
  }

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}

/// Notifier whose async applyEvent throws for certain events.
class _ErrorNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  Future<int> applyEvent(int state, CounterEvent event) async {
    if (event is SetCount && event.value < 0) {
      await Future<void>.delayed(Duration(milliseconds: 5));
      throw Exception('negative value not allowed');
    }
    await Future<void>.delayed(Duration(milliseconds: 5));
    return reduce(state, event);
  }

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}

/// Notifier with mixed sync/async behavior in applyEvent.
/// SetCount is async, everything else is sync.
class _MixedNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  Future<int> applyEvent(int state, CounterEvent event) async {
    if (event is SetCount) {
      await Future<void>.delayed(Duration(milliseconds: 10));
    }
    return reduce(state, event);
  }

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}
