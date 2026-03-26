import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// --- Family notifier: initial state = constructor arg ---

class FamilyCounterNotifier extends ReducerNotifier<int, CounterEvent> {
  FamilyCounterNotifier(this.startValue);
  final int startValue;

  @override
  int initialState() => startValue;

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}

// --- Family notifier with bindings: multiplier affects bound value ---

class FamilyBoundNotifier extends ReducerNotifier<BoundState, BoundEvent> {
  FamilyBoundNotifier(this.multiplier);
  final int multiplier;

  @override
  BoundState initialState() => BoundState(externalCount: 0, internalCount: 0);

  @override
  void bindings() {
    bind<int>(
      externalCountProvider,
      (_, next) => ExternalCountChanged(next * multiplier),
    );
  }

  @override
  BoundState reduce(BoundState state, BoundEvent event) => switch (event) {
    ExternalCountChanged(:final value) => state.copyWith(externalCount: value),
    InternalIncrement() => state.copyWith(
      internalCount: state.internalCount + 1,
    ),
  };
}

// --- Auto-dispose notifier with bindings ---

class AutoDisposeBoundNotifier extends ReducerNotifier<BoundState, BoundEvent> {
  @override
  BoundState initialState() => BoundState(externalCount: 0, internalCount: 0);

  @override
  void bindings() {
    bind<int>(externalCountProvider, (_, next) => ExternalCountChanged(next));
  }

  @override
  BoundState reduce(BoundState state, BoundEvent event) => switch (event) {
    ExternalCountChanged(:final value) => state.copyWith(externalCount: value),
    InternalIncrement() => state.copyWith(
      internalCount: state.internalCount + 1,
    ),
  };
}

void main() {
  // ========================================================
  // NotifierProvider.autoDispose
  // ========================================================
  group('NotifierProvider.autoDispose', () {
    final autoCounterProvider =
        NotifierProvider.autoDispose<CounterNotifier, int>(CounterNotifier.new);

    test('initialState works', () {
      final container = createContainer();
      final sub = container.listen(autoCounterProvider, (_, _) {});
      expect(container.read(autoCounterProvider), 0);
      sub.close();
    });

    test('dispatch updates state', () {
      final container = createContainer();
      final sub = container.listen(autoCounterProvider, (_, _) {});

      container.read(autoCounterProvider.notifier).dispatch(Increment());
      container.read(autoCounterProvider.notifier).dispatch(Increment());
      expect(container.read(autoCounterProvider), 2);

      container.read(autoCounterProvider.notifier).dispatch(SetCount(10));
      expect(container.read(autoCounterProvider), 10);
      sub.close();
    });

    test('bindings fire on init and on dependency change', () {
      final autoBoundProvider =
          NotifierProvider.autoDispose<AutoDisposeBoundNotifier, BoundState>(
            AutoDisposeBoundNotifier.new,
          );

      final container = createContainer();
      final sub = container.listen(autoBoundProvider, (_, _) {});

      // Initial bind fires with externalCountProvider default (10)
      expect(container.read(autoBoundProvider).externalCount, 10);

      // Dependency change propagates
      container.read(externalCountProvider.notifier).state = 50;
      expect(container.read(autoBoundProvider).externalCount, 50);

      // User dispatch works alongside
      container.read(autoBoundProvider.notifier).dispatch(InternalIncrement());
      expect(container.read(autoBoundProvider).internalCount, 1);

      sub.close();
    });

    test('re-initializes after disposal', () async {
      final autoBoundProvider =
          NotifierProvider.autoDispose<AutoDisposeBoundNotifier, BoundState>(
            AutoDisposeBoundNotifier.new,
          );

      final container = createContainer();

      // First subscription
      final sub1 = container.listen(autoBoundProvider, (_, _) {});
      container.read(autoBoundProvider.notifier).dispatch(InternalIncrement());
      container.read(autoBoundProvider.notifier).dispatch(InternalIncrement());
      expect(container.read(autoBoundProvider).internalCount, 2);
      sub1.close();

      // Let auto-dispose run
      await container.pump();

      // After disposal and re-read, state is fresh
      final sub2 = container.listen(autoBoundProvider, (_, _) {});
      expect(container.read(autoBoundProvider).internalCount, 0);
      expect(container.read(autoBoundProvider).externalCount, 10); // re-bound
      sub2.close();
    });
  });

  // ========================================================
  // NotifierProvider.family
  // ========================================================
  group('NotifierProvider.family', () {
    final familyCounterProvider =
        NotifierProvider.family<FamilyCounterNotifier, int, int>(
          FamilyCounterNotifier.new,
        );

    test('constructor arg sets initial state', () {
      final container = createContainer();
      expect(container.read(familyCounterProvider(10)), 10);
      expect(container.read(familyCounterProvider(42)), 42);
      expect(container.read(familyCounterProvider(0)), 0);
    });

    test('different family keys have independent state', () {
      final container = createContainer();

      container.read(familyCounterProvider(10).notifier).dispatch(Increment());
      container.read(familyCounterProvider(10).notifier).dispatch(Increment());

      expect(container.read(familyCounterProvider(10)), 12); // 10 + 2
      expect(container.read(familyCounterProvider(42)), 42); // untouched
    });

    test('dispatch on one key does not affect another', () {
      final container = createContainer();

      container.read(familyCounterProvider(0).notifier).dispatch(SetCount(99));
      container.read(familyCounterProvider(1).notifier).dispatch(Increment());

      expect(container.read(familyCounterProvider(0)), 99);
      expect(container.read(familyCounterProvider(1)), 2); // 1 + 1
    });

    test('bindings work per-family instance with different args', () {
      final familyBoundProvider =
          NotifierProvider.family<FamilyBoundNotifier, BoundState, int>(
            FamilyBoundNotifier.new,
          );

      final container = createContainer();

      // multiplier=1: externalCount = 10 * 1 = 10
      final state1 = container.read(familyBoundProvider(1));
      expect(state1.externalCount, 10);

      // multiplier=3: externalCount = 10 * 3 = 30
      final state3 = container.read(familyBoundProvider(3));
      expect(state3.externalCount, 30);

      // Change dependency — both update with their own multiplier
      container.read(externalCountProvider.notifier).state = 5;
      expect(container.read(familyBoundProvider(1)).externalCount, 5);
      expect(container.read(familyBoundProvider(3)).externalCount, 15);
    });
  });

  // ========================================================
  // NotifierProvider.autoDispose.family
  // ========================================================
  group('NotifierProvider.autoDispose.family', () {
    final autoFamilyProvider = NotifierProvider.autoDispose
        .family<FamilyCounterNotifier, int, int>(FamilyCounterNotifier.new);

    test('arg-based initial state works', () {
      final container = createContainer();
      final sub = container.listen(autoFamilyProvider(7), (_, _) {});
      expect(container.read(autoFamilyProvider(7)), 7);
      sub.close();
    });

    test('independent state per key', () {
      final container = createContainer();
      final sub1 = container.listen(autoFamilyProvider(10), (_, _) {});
      final sub2 = container.listen(autoFamilyProvider(20), (_, _) {});

      container.read(autoFamilyProvider(10).notifier).dispatch(Increment());
      expect(container.read(autoFamilyProvider(10)), 11);
      expect(container.read(autoFamilyProvider(20)), 20); // untouched

      sub1.close();
      sub2.close();
    });

    test('each key auto-disposes separately', () async {
      final container = createContainer();

      // Subscribe to key=5 and key=10
      final sub5 = container.listen(autoFamilyProvider(5), (_, _) {});
      final sub10 = container.listen(autoFamilyProvider(10), (_, _) {});

      // Mutate both
      container.read(autoFamilyProvider(5).notifier).dispatch(Increment());
      container.read(autoFamilyProvider(10).notifier).dispatch(Increment());
      expect(container.read(autoFamilyProvider(5)), 6);
      expect(container.read(autoFamilyProvider(10)), 11);

      // Close only key=5
      sub5.close();

      // Let auto-dispose run for key=5
      await container.pump();

      // key=10 is still alive
      expect(container.read(autoFamilyProvider(10)), 11);

      // Re-subscribe to key=5 — fresh state
      final sub5b = container.listen(autoFamilyProvider(5), (_, _) {});
      expect(container.read(autoFamilyProvider(5)), 5); // re-initialized

      sub5b.close();
      sub10.close();
    });

    test('bindings work with auto-dispose family', () {
      final autoFamilyBoundProvider = NotifierProvider.autoDispose
          .family<FamilyBoundNotifier, BoundState, int>(
            FamilyBoundNotifier.new,
          );

      final container = createContainer();
      final sub = container.listen(autoFamilyBoundProvider(2), (_, _) {});

      // multiplier=2: externalCount = 10 * 2 = 20
      expect(container.read(autoFamilyBoundProvider(2)).externalCount, 20);

      // Dependency change
      container.read(externalCountProvider.notifier).state = 7;
      expect(container.read(autoFamilyBoundProvider(2)).externalCount, 14);

      sub.close();
    });
  });
}
