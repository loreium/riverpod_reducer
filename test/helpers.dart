import 'package:riverpod/legacy.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- Counter events ---

sealed class CounterEvent {}

class Increment extends CounterEvent {}

class Decrement extends CounterEvent {}

class SetCount extends CounterEvent {
  SetCount(this.value);
  final int value;
}

class Reset extends CounterEvent {}

// --- Counter notifier ---

class CounterNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
    SetCount(:final value) => value,
    Reset() => 0,
  };
}

final counterProvider = NotifierProvider<CounterNotifier, int>(
  CounterNotifier.new,
);

// --- Binding notifier (binds to an external StateProvider) ---

final externalCountProvider = StateProvider<int>((ref) => 10);

sealed class BoundEvent {}

class ExternalCountChanged extends BoundEvent {
  ExternalCountChanged(this.value);
  final int value;
}

class InternalIncrement extends BoundEvent {}

class BoundState {
  BoundState({required this.externalCount, required this.internalCount});

  final int externalCount;
  final int internalCount;

  BoundState copyWith({int? externalCount, int? internalCount}) => BoundState(
    externalCount: externalCount ?? this.externalCount,
    internalCount: internalCount ?? this.internalCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundState &&
          externalCount == other.externalCount &&
          internalCount == other.internalCount;

  @override
  int get hashCode => Object.hash(externalCount, internalCount);
}

class BoundNotifier extends ReducerNotifier<BoundState, BoundEvent> {
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

final boundProvider = NotifierProvider<BoundNotifier, BoundState>(
  BoundNotifier.new,
);

// --- Middleware notifier ---

class LoggingNotifier extends ReducerNotifier<int, CounterEvent> {
  final List<CounterEvent> eventLog = [];

  @override
  int initialState() => 0;

  @override
  int applyEvent(int state, CounterEvent event) {
    eventLog.add(event);
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

final loggingProvider = NotifierProvider<LoggingNotifier, int>(
  LoggingNotifier.new,
);

// --- Helper to create ProviderContainer with cleanup ---

ProviderContainer createContainer({List<Override> overrides = const []}) {
  return ProviderContainer.test(overrides: overrides);
}
