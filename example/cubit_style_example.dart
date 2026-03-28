/// Cubit / Riverpod Style — public methods on the notifier.
///
/// Side effects live in methods. State transitions go through [dispatch].
/// The [reduce] function stays pure.
library;

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- State ---

class TodoState {
  TodoState({required this.todos, required this.syncing, this.error});

  final List<String> todos;
  final bool syncing;
  final String? error;

  TodoState copyWith({
    List<String>? todos,
    bool? syncing,
    String? Function()? error,
  }) => TodoState(
    todos: todos ?? this.todos,
    syncing: syncing ?? this.syncing,
    error: error != null ? error() : this.error,
  );
}

// --- Events ---

sealed class TodoEvent {}

class TodoAdded extends TodoEvent {
  TodoAdded(this.text);
  final String text;
}

class TodoRemoved extends TodoEvent {
  TodoRemoved(this.index);
  final int index;
}

class SyncStarted extends TodoEvent {}

class SyncCompleted extends TodoEvent {}

class SyncFailed extends TodoEvent {
  SyncFailed(this.message);
  final String message;
}

// --- Notifier ---

class TodoNotifier extends ReducerNotifier<TodoState, TodoEvent> {
  @override
  TodoState initialState() => TodoState(todos: [], syncing: false);

  @override
  TodoState reduce(TodoState state, TodoEvent event) => switch (event) {
    TodoAdded(:final text) => state.copyWith(todos: [...state.todos, text]),
    TodoRemoved(:final index) => state.copyWith(
      todos: [...state.todos]..removeAt(index),
    ),
    SyncStarted() => state.copyWith(syncing: true, error: () => null),
    SyncCompleted() => state.copyWith(syncing: false),
    SyncFailed(:final message) => state.copyWith(
      syncing: false,
      error: () => message,
    ),
  };

  /// Add a todo item.
  void addTodo(String text) => dispatch(TodoAdded(text));

  /// Remove a todo by index.
  void removeTodo(int index) => dispatch(TodoRemoved(index));

  /// Sync todos with the server. Side effects live here in the method.
  Future<void> syncWithServer() async {
    await dispatch(SyncStarted());
    try {
      // Simulate API call
      await Future<void>.delayed(Duration(milliseconds: 500));
      await dispatch(SyncCompleted());
    } catch (e) {
      await dispatch(SyncFailed(e.toString()));
    }
  }
}

// --- Provider ---

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);

// --- Usage ---
//
// // In a widget:
// ref.read(todoProvider.notifier).addTodo('Buy groceries');
// ref.read(todoProvider.notifier).removeTodo(0);
// await ref.read(todoProvider.notifier).syncWithServer();
//
// // Watch state:
// final state = ref.watch(todoProvider);
// for (final todo in state.todos) { ... }
// if (state.syncing) showSpinner();
// if (state.error case final msg?) showError(msg);
