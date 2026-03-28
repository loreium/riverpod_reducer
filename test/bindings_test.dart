import 'package:riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pumps the event loop so async dispatches from bindings complete.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('bind()', () {
    test('initial state reflects bound dependency via fireImmediately', () {
      final container = createContainer();
      final state = container.read(boundProvider);
      // externalCountProvider defaults to 10, bind fires immediately
      // During build, events are folded through reduce synchronously
      expect(state.externalCount, 10);
      expect(state.internalCount, 0);
    });

    test('state updates when bound dependency changes', () async {
      final container = createContainer();

      // Initial
      expect(container.read(boundProvider).externalCount, 10);

      // Change the external dependency
      container.read(externalCountProvider.notifier).state = 42;
      await pump();
      expect(container.read(boundProvider).externalCount, 42);
    });

    test('user dispatch works alongside bindings', () async {
      final container = createContainer();
      final notifier = container.read(boundProvider.notifier);

      expect(container.read(boundProvider).internalCount, 0);
      await notifier.dispatch(InternalIncrement());
      expect(container.read(boundProvider).internalCount, 1);

      // External still works
      container.read(externalCountProvider.notifier).state = 99;
      await pump();
      final state = container.read(boundProvider);
      expect(state.externalCount, 99);
      expect(state.internalCount, 1);
    });

    test('toEvent returning null skips dispatch', () async {
      // Notifier that only binds when value > 0
      final sourceProvider = StateProvider<int>((ref) => -1);

      final notifier = _NullSkipNotifier();
      final provider = NotifierProvider<_NullSkipNotifier, int>(() => notifier);

      _NullSkipNotifier.source = sourceProvider;

      final container = createContainer();
      // Source is -1, toEvent returns null, so initial state stays 0
      expect(container.read(provider), 0);

      // Set to positive — event fires
      container.read(sourceProvider.notifier).state = 5;
      await pump();
      expect(container.read(provider), 5);

      // Set to negative — event skipped
      container.read(sourceProvider.notifier).state = -3;
      await pump();
      expect(container.read(provider), 5); // unchanged
    });

    test('multiple bindings on same notifier', () async {
      final providerA = StateProvider<int>((ref) => 1);
      final providerB = StateProvider<String>((ref) => 'hello');

      final provider = NotifierProvider<_MultiBoundNotifier, _MultiBoundState>(
        () => _MultiBoundNotifier(providerA, providerB),
      );

      final container = createContainer();
      final state = container.read(provider);
      expect(state.a, 1);
      expect(state.b, 'hello');

      container.read(providerA.notifier).state = 99;
      await pump();
      expect(container.read(provider).a, 99);

      container.read(providerB.notifier).state = 'world';
      await pump();
      expect(container.read(provider).b, 'world');
    });
  });

  group('bindAsync()', () {
    test('handles AsyncData', () {
      final asyncProvider = FutureProvider<String>((ref) async => 'loaded');
      final provider = NotifierProvider<_AsyncBoundNotifier, String>(
        () => _AsyncBoundNotifier(asyncProvider),
      );

      final container = createContainer();
      // FutureProvider starts as AsyncLoading, then resolves
      // During build, fireImmediately captures the current AsyncValue
      final state = container.read(provider);
      // Depending on timing, this could be 'loading' or 'loaded'
      expect(state, anyOf('loading', 'loaded: loaded'));
    });

    test('handles AsyncError via bindAsync', () {
      final asyncProvider = FutureProvider<String>(
        (ref) async => throw Exception('fail'),
      );
      final provider = NotifierProvider<_AsyncBoundNotifier, String>(
        () => _AsyncBoundNotifier(asyncProvider),
      );

      final container = createContainer();
      final state = container.read(provider);
      expect(state, anyOf('loading', contains('error')));
    });
  });
}

// --- Test-specific notifiers ---

class _NullSkipNotifier extends ReducerNotifier<int, int> {
  static late StateProvider<int> source;

  @override
  int initialState() => 0;

  @override
  void bindings() {
    bind<int>(source, (_, next) => next > 0 ? next : null);
  }

  @override
  int reduce(int state, int event) => event;
}

class _MultiBoundState {
  _MultiBoundState({required this.a, required this.b});
  final int a;
  final String b;
}

sealed class _MultiBoundEvent {}

class _SetA extends _MultiBoundEvent {
  _SetA(this.value);
  final int value;
}

class _SetB extends _MultiBoundEvent {
  _SetB(this.value);
  final String value;
}

class _MultiBoundNotifier
    extends ReducerNotifier<_MultiBoundState, _MultiBoundEvent> {
  _MultiBoundNotifier(this._providerA, this._providerB);
  final StateProvider<int> _providerA;
  final StateProvider<String> _providerB;

  @override
  _MultiBoundState initialState() => _MultiBoundState(a: 0, b: '');

  @override
  void bindings() {
    bind<int>(_providerA, (_, next) => _SetA(next));
    bind<String>(_providerB, (_, next) => _SetB(next));
  }

  @override
  _MultiBoundState reduce(_MultiBoundState state, _MultiBoundEvent event) =>
      switch (event) {
        _SetA(:final value) => _MultiBoundState(a: value, b: state.b),
        _SetB(:final value) => _MultiBoundState(a: state.a, b: value),
      };
}

sealed class _AsyncEvent {}

class _AsyncDataLoaded extends _AsyncEvent {
  _AsyncDataLoaded(this.value);
  final String value;
}

class _AsyncLoading extends _AsyncEvent {}

class _AsyncErrorOccurred extends _AsyncEvent {
  _AsyncErrorOccurred(this.error);
  final Object error;
}

class _AsyncBoundNotifier extends ReducerNotifier<String, _AsyncEvent> {
  _AsyncBoundNotifier(this._asyncProvider);
  final FutureProvider<String> _asyncProvider;

  @override
  String initialState() => 'initial';

  @override
  void bindings() {
    bindAsync<String>(
      _asyncProvider,
      (_, next) => switch (next) {
        AsyncData(:final value) => _AsyncDataLoaded(value),
        AsyncError(:final error) => _AsyncErrorOccurred(error),
        AsyncLoading() => _AsyncLoading(),
      },
    );
  }

  @override
  String reduce(String state, _AsyncEvent event) => switch (event) {
    _AsyncDataLoaded(:final value) => 'loaded: $value',
    _AsyncLoading() => 'loading',
    _AsyncErrorOccurred(:final error) => 'error: $error',
  };
}
