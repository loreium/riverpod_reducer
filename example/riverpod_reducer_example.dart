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
}

final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
);

// --- Usage ---

void main() {
  final container = ProviderContainer();

  // Read initial state
  print('Initial: ${container.read(counterProvider)}'); // 0

  // Dispatch events
  container.read(counterProvider.notifier).dispatch(Increment());
  container.read(counterProvider.notifier).dispatch(Increment());
  print('After 2x Increment: ${container.read(counterProvider)}'); // 2

  container.read(counterProvider.notifier).dispatch(Decrement());
  print('After Decrement: ${container.read(counterProvider)}'); // 1

  container.read(counterProvider.notifier).dispatch(Reset());
  print('After Reset: ${container.read(counterProvider)}'); // 0

  // Test reduce() in isolation — no ProviderContainer needed:
  final notifier = CounterNotifier();
  assert(notifier.reduce(5, Increment()) == 6);
  assert(notifier.reduce(5, Decrement()) == 4);
  assert(notifier.reduce(99, Reset()) == 0);
  print('Pure reduce tests passed!');

  container.dispose();
}
