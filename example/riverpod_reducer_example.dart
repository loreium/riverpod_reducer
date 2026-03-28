import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- Events ---

sealed class CounterEvent {}

class Increment extends CounterEvent {}

class Decrement extends CounterEvent {}

class Reset extends CounterEvent {}

// --- Notifier ---

class CounterNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    Reset() => 0,
  };

  void increment() => dispatch(Increment());
  void decrement() => dispatch(Decrement());
  void reset() => dispatch(Reset());
}

final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
);

// --- Usage ---

void main() {
  final container = ProviderContainer();
  final notifier = container.read(counterProvider.notifier);

  // Read initial state
  print('Initial: ${container.read(counterProvider)}'); // 0

  // Call methods on the notifier
  notifier.increment();
  notifier.increment();
  print('After 2x increment: ${container.read(counterProvider)}'); // 2

  notifier.decrement();
  print('After decrement: ${container.read(counterProvider)}'); // 1

  notifier.reset();
  print('After reset: ${container.read(counterProvider)}'); // 0

  // Test reduce() in isolation — no ProviderContainer needed:
  final testNotifier = CounterNotifier();
  assert(testNotifier.reduce(5, Increment()) == 6);
  assert(testNotifier.reduce(5, Decrement()) == 4);
  assert(testNotifier.reduce(99, Reset()) == 0);
  print('Pure reduce tests passed!');

  container.dispose();
}
