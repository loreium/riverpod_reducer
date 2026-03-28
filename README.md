# riverpod_reducer

[![CI](https://github.com/loreium/riverpod_reducer/actions/workflows/ci.yml/badge.svg)](https://github.com/loreium/riverpod_reducer/actions/workflows/ci.yml)
[![preview](https://img.shields.io/badge/status-preview-orange)](https://github.com/loreium/riverpod_reducer)

A pure reducer pattern for [Riverpod](https://riverpod.dev) notifiers. Requires Riverpod 3.x.

> **Note:** This package is in preview. The API may change before 1.0.

## The Problem

Riverpod's `build()` conflates reactive subscriptions with state initialization. This isn't an issue for simple providers, but it breaks down for **view models**, a very common pattern in app development, where you mix internal UI state with external reactive dependencies.

Consider a form screen that tracks user input (tabs, text fields, checkboxes) while also reacting to external data (current user, theme, permissions). In vanilla Riverpod, you're forced to put both in `build()`:

```dart
class FormNotifier extends Notifier<FormState> {
  @override
  FormState build() {
    final user = ref.watch(userProvider);       // external dep
    final config = ref.watch(configProvider);    // external dep
    return FormState(
      user: user,
      config: config,
      selectedTab: 0,    // internal state: resets!
      searchQuery: '',   // internal state: resets!
      isDirty: false,    // internal state: resets!
    );
  }
}
```

Every time `userProvider` or `configProvider` changes, `build()` re-runs and all internal state is lost. The selected tab jumps back to 0, the search query clears, the dirty flag resets.

There are workarounds (`listenSelf`, manual state caching, `ref.listen` instead of `ref.watch`, splitting state across multiple providers) but they all break the view model pattern. Instead of one notifier that owns a screen's state, you end up with scattered listeners, manual synchronization logic, or a constellation of providers that have to be composed back together in the widget. The cure is worse than the disease.

The root cause: `build()` serves two purposes that shouldn't be coupled. It both **subscribes to dependencies** and **initializes state**. When one triggers, the other re-executes.

## The Solution

`riverpod_reducer` is a lightweight version of the classical store pattern (Redux, Elm) adapted for the Riverpod world and simplified down to what you actually need: a single base class with three methods.

External dependency changes are mapped to typed events via `bindings()` and routed through a pure `reduce(State, Event) -> State` function. The same function that handles user-triggered events. The reducer doesn't care where the event came from.

```dart
class FormNotifier extends ReducerNotifier<FormState, FormEvent> {
  @override
  FormState initialState() => FormState.initial();

  @override
  void bindings() {
    bind(userProvider, (_, user) => UserLoaded(user));
    bind(configProvider, (_, config) => ConfigUpdated(config));
  }

  @override
  FormState reduce(FormState state, FormEvent event) => switch (event) {
    UserLoaded(:final user) => state.copyWith(user: user),
    ConfigUpdated(:final config) => state.copyWith(config: config),
    TabSelected(:final index) => state.copyWith(selectedTab: index),
    SearchChanged(:final query) => state.copyWith(searchQuery: query),
  };

  void selectTab(int index) => dispatch(TabSelected(index: index));
  void search(String query) => dispatch(SearchChanged(query: query));
}
```

When `userProvider` changes, only `UserLoaded` fires through `reduce()`. The selected tab, search query, and every other piece of internal state is preserved because `reduce()` only touches what the event tells it to.

## Quick Start

Add to your `pubspec.yaml`:

```yaml
dependencies:
  riverpod_reducer: ^0.1.0
```

### Define events and state

```dart
sealed class CounterEvent {}
class Increment extends CounterEvent {}
class Decrement extends CounterEvent {}
```

### Create the notifier

```dart
class CounterNotifier extends ReducerNotifier<int, CounterEvent> {
  @override
  int initialState() => 0;

  @override
  int reduce(int state, CounterEvent event) => switch (event) {
    Increment() => state + 1,
    Decrement() => state - 1,
  };

  void increment() => dispatch(Increment());
  void decrement() => dispatch(Decrement());
}

final counterProvider =
    NotifierProvider<CounterNotifier, int>(CounterNotifier.new);
```

### Use from UI

```dart
// In a widget:
ref.read(counterProvider.notifier).increment();
```

## Core Concepts

### `initialState()`

Returns the default state. No watches, no listens, just a value.

### `reduce(State state, Event event)`

Pure function. ALL state transitions go through here. No side effects, no async, no ref access. This is what makes the pattern testable.

### `bindings()`

Declares reactive subscriptions. Called automatically after `initialState()`. Uses `bind()` and `bindAsync()` to map provider changes to events:

```dart
@override
void bindings() {
  bind(userProvider, (_, user) => UserLoaded(user));
  bindAsync<Config>(configProvider, (_, value) => switch (value) {
    AsyncData(:final value) => ConfigLoaded(value),
    AsyncError(:final error) => ConfigError(error),
    _ => null, // return null to skip dispatch
  });
}
```

### `dispatch(Event event)`

Triggers `middleware()` → `reduce()` and updates state. Protected — call it from within named methods on your notifier. Marked `@visibleForTesting` so tests can call it directly.

### `middleware(State state, Event event)`

Async event filter/transformer. Override to intercept, transform, or drop events before they reach `reduce()`:

- Return the event (or a modified event) to pass it to `reduce()`
- Return `null` to drop/block the event

```dart
@override
Future<MyEvent?> middleware(MyState state, MyEvent event) async {
  logger.log(event);
  if (event is Blocked) return null; // drop
  return event;
}
```

Events are processed sequentially — if a previous event is still being handled, new dispatches queue behind it.

## Usage Patterns

### Side effects in methods

Named methods on the notifier handle async work and call `dispatch()` for state transitions. The `reduce()` function stays pure.

```dart
class TodoNotifier extends ReducerNotifier<TodoState, TodoEvent> {
  @override
  TodoState initialState() => TodoState(todos: [], syncing: false);

  @override
  TodoState reduce(TodoState state, TodoEvent event) => switch (event) {
    TodoAdded(:final text) => state.copyWith(todos: [...state.todos, text]),
    SyncStarted() => state.copyWith(syncing: true),
    SyncCompleted() => state.copyWith(syncing: false),
    SyncFailed(:final message) => state.copyWith(syncing: false, error: message),
  };

  void addTodo(String text) => dispatch(TodoAdded(text));

  Future<void> sync() async {
    await dispatch(SyncStarted());
    try {
      await api.sync(state.todos);
      await dispatch(SyncCompleted());
    } catch (e) {
      await dispatch(SyncFailed(e.toString()));
    }
  }
}
```

## Idempotent Reducers for Bindings

Riverpod may re-deliver the current value when a provider rebuilds, meaning binding events can be **replayed**. Your `reduce` function must handle binding events idempotently — applying the same event to the same state must produce the same state. In practice this means: **set values, don't accumulate them**.

```dart
// Good — idempotent: applying UserLoaded('Alice') twice is harmless
UserLoaded(:final name) => state.copyWith(userName: name),

// Bad — not idempotent: each replay adds a duplicate entry
ItemReceived(:final item) => state.copyWith(items: [...state.items, item]),
```

This only applies to **bindings**. Events dispatched directly from UI callbacks or other one-shot actions (e.g. `notifier.increment()` on button press) are triggered exactly once by the caller and are not subject to replay.

## Testing

### Test `reduce()` in isolation (no framework needed)

```dart
test('reduce is pure and testable', () {
  final notifier = CounterNotifier();
  expect(notifier.reduce(0, Increment()), 1);
  expect(notifier.reduce(5, Decrement()), 4);
});
```

### Integration test with ProviderContainer

```dart
test('dispatch updates state', () async {
  final container = ProviderContainer.test();
  await container.read(counterProvider.notifier).dispatch(Increment());
  expect(container.read(counterProvider), 1);
});
```

### Test bindings with overrides

```dart
test('binding reflects dependency', () {
  final container = ProviderContainer.test(
    overrides: [userProvider.overrideWith((ref) => 'TestUser')],
  );
  expect(container.read(formProvider).userName, 'TestUser');
});
```

## Auto-Dispose and Family

Riverpod 3.x unifies all notifier types. Use `ReducerNotifier` with any provider variant:

```dart
// Auto-dispose
final provider = NotifierProvider.autoDispose<MyNotifier, MyState>(MyNotifier.new);

// Family
class MyNotifier extends ReducerNotifier<MyState, MyEvent> {
  MyNotifier(this.id);
  final String id;
  // ...
}
final provider = NotifierProvider.family<MyNotifier, MyState, String>(MyNotifier.new);
```

## Why This Pattern

This is the classical store pattern (Redux, Elm, MVU) distilled to its simplest useful form for Riverpod. No action creators, no boilerplate. Just `initialState`, `bindings`, and `reduce` — with an optional `middleware` hook for event interception.

- **Testable**: `reduce()` is a pure function. Test every state transition with zero mocking, no `ProviderContainer`, no framework setup.
- **Predictable**: One function handles ALL state transitions. No hidden rebuilds, no state resets, no scattered `state =` assignments across methods.
- **View-model friendly**: Internal UI state and external reactive dependencies coexist without fighting each other. This is the primary use case.
- **Familiar**: If you know Redux, Elm, or Bloc events, you already know this. If you don't, the API surface is three methods.

## Comparison

| Feature | Riverpod Notifier | Bloc | riverpod_reducer |
|---|---|---|---|
| Pure reducer | No | No (async handlers) | Yes |
| Reactive deps | Yes (watch in build) | No (manual streams) | Yes (bind) |
| State resets on dep change | Yes | N/A | No |
| Typed events | No | Yes | Yes |
| Testable without framework | No | Partially | Yes |

## Compatibility

- Dart SDK `>=3.7.0`
- `riverpod: ^3.0.0`
- Works with `flutter_riverpod` (riverpod is a transitive dependency)
