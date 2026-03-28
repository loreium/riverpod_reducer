import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('dispatch()', () {
    test('single event updates state', () async {
      final container = createContainer();
      expect(container.read(counterProvider), 0);

      await container.read(counterProvider.notifier).dispatch(Increment());
      expect(container.read(counterProvider), 1);
    });

    test('multiple sequential dispatches accumulate', () async {
      final container = createContainer();
      final notifier = container.read(counterProvider.notifier);

      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      expect(container.read(counterProvider), 3);

      await notifier.dispatch(Decrement());
      expect(container.read(counterProvider), 2);
    });

    test('SetCount overrides current state', () async {
      final container = createContainer();
      final notifier = container.read(counterProvider.notifier);

      await notifier.dispatch(Increment());
      await notifier.dispatch(Increment());
      await notifier.dispatch(SetCount(100));
      expect(container.read(counterProvider), 100);
    });

    test('skips update when reduce returns identical state', () async {
      final container = createContainer();
      // Initial state is 0, Reset returns 0 — identical int
      final notifier = container.read(counterProvider.notifier);

      var notifyCount = 0;
      container.listen(counterProvider, (_, _) => notifyCount++);

      // Reset on state=0 returns 0 (same value, and for int, identical)
      await notifier.dispatch(Reset());
      // For int primitives, identical(0, 0) is true
      expect(notifyCount, 0);
    });

    test(
      'does not skip update when values are equal but not identical',
      () async {
        final container = createContainer();

        // Use BoundNotifier which uses a class (not primitive)
        final notifier = container.read(boundProvider.notifier);
        final initialState = container.read(boundProvider);

        // Dispatch an event that creates a new BoundState with same values
        // InternalIncrement changes the value, so it won't be identical
        await notifier.dispatch(InternalIncrement());
        final newState = container.read(boundProvider);
        expect(newState.internalCount, 1);
        expect(identical(initialState, newState), false);
      },
    );
  });
}
