import 'package:meta/meta.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:riverpod/riverpod.dart';

/// An abstract base class that adds a pure reducer pattern to Riverpod's
/// [Notifier].
///
/// Instead of overriding [build], subclasses implement:
/// - [initialState] — returns the default state value
/// - [bindings] — declares reactive subscriptions via [bind] and [bindAsync]
/// - [reduce] — pure function: `(State, Event) → State`
///
/// All state transitions flow through [reduce], making them testable,
/// predictable, and independent of the Riverpod framework.
///
/// ```dart
/// class CounterNotifier extends ReducerNotifier<int, CounterEvent> {
///   @override
///   int initialState() => 0;
///
///   @override
///   int reduce(int state, CounterEvent event) => switch (event) {
///     Increment() => state + 1,
///     Decrement() => state - 1,
///   };
/// }
/// ```
abstract class ReducerNotifier<S, E> extends Notifier<S> {
  bool _initializing = false;
  final List<E> _pendingEvents = [];

  /// Returns the initial state. Called once per build cycle.
  ///
  /// Do NOT use `ref.watch` or `ref.listen` here — use [bindings] instead.
  S initialState();

  /// Pure reducer function. Given current [state] and an [event],
  /// returns the new state.
  ///
  /// Must be a pure function with no side effects, no async, no ref access.
  ///
  /// **Important:** For events originating from [bind]/[bindAsync], the
  /// reducer must be **idempotent**: applying the same event to the same
  /// state twice must return the same state. Use `copyWith`-style updates
  /// (set the value) rather than incremental mutations (add to the value).
  ///
  /// ```dart
  /// // Good — idempotent: applying UserLoaded('Alice') twice is harmless
  /// UserLoaded(:final name) => state.copyWith(userName: name),
  ///
  /// // Bad — not idempotent: each replay adds a duplicate entry
  /// ItemReceived(:final item) => state.copyWith(items: [...state.items, item]),
  /// ```
  S reduce(S state, E event);

  /// Override to bind external providers via [bind] and [bindAsync].
  ///
  /// Called automatically during each build cycle after [initialState].
  /// Subscriptions are cleaned up and re-established on rebuild.
  @protected
  void bindings() {}

  /// Middleware hook. Override to intercept events for logging, analytics,
  /// or conditional event handling.
  ///
  /// Default implementation delegates to [reduce].
  ///
  /// ```dart
  /// @override
  /// MyState applyEvent(MyState state, MyEvent event) {
  ///   log('Event: ${event.runtimeType}');
  ///   return reduce(state, event);
  /// }
  /// ```
  @protected
  S applyEvent(S state, E event) => reduce(state, event);

  /// Dispatches an [event], triggering [applyEvent] → [reduce].
  ///
  /// During initialization (inside [build]), events are queued and applied
  /// after [bindings] completes. After initialization, events are applied
  /// immediately and the state is updated if the new state is not identical
  /// to the current state.
  void dispatch(E event) {
    if (_initializing) {
      _pendingEvents.add(event);
      return;
    }
    final next = applyEvent(state, event);
    if (!identical(next, state)) {
      state = next;
    }
  }

  /// Binds a provider so that changes automatically dispatch events.
  ///
  /// Uses `ref.listen` with `fireImmediately: true` so the current value
  /// is captured on initialization. If [toEvent] returns `null`, the
  /// dispatch is skipped.
  ///
  /// **Warning:** Riverpod may re-deliver the current value on provider
  /// rebuild, so binding events can be replayed. The [reduce] function must
  /// handle these events idempotently — see [reduce] for details.
  ///
  /// ```dart
  /// @override
  /// void bindings() {
  ///   bind(userProvider, (_, user) => UserLoaded(user));
  /// }
  /// ```
  @protected
  void bind<T>(
    ProviderListenable<T> provider,
    E? Function(T? previous, T next) toEvent,
  ) {
    ref.listen<T>(provider, (previous, next) {
      final event = toEvent(previous, next);
      if (event != null) dispatch(event);
    }, fireImmediately: true);
  }

  /// Binds an async provider, dispatching events for [AsyncValue] phases.
  ///
  /// Similar to [bind], but typed for providers that expose [AsyncValue].
  /// If [toEvent] returns `null`, the dispatch is skipped.
  ///
  /// **Warning:** Binding events can be replayed — see [bind] and [reduce].
  ///
  /// ```dart
  /// @override
  /// void bindings() {
  ///   bindAsync<User>(asyncUserProvider, (_, value) => switch (value) {
  ///     AsyncData(:final value) => UserLoaded(value),
  ///     AsyncError(:final error) => UserError(error),
  ///     _ => null,
  ///   });
  /// }
  /// ```
  @protected
  void bindAsync<T>(
    ProviderListenable<AsyncValue<T>> provider,
    E? Function(AsyncValue<T>? previous, AsyncValue<T> next) toEvent,
  ) {
    ref.listen<AsyncValue<T>>(provider, (previous, next) {
      final event = toEvent(previous, next);
      if (event != null) dispatch(event);
    }, fireImmediately: true);
  }

  /// The build lifecycle — owned by [ReducerNotifier].
  ///
  /// Calls [initialState], then [bindings] (which queues initial events
  /// via [bind]/[bindAsync]), then folds all queued events through
  /// [applyEvent] to produce the final initial state.
  ///
  /// **Do not override.** Implement [initialState] and [bindings] instead.
  @override
  @nonVirtual
  S build() {
    _initializing = true;
    _pendingEvents.clear();
    final initial = initialState();
    bindings();
    _initializing = false;
    var s = initial;
    for (final event in _pendingEvents) {
      s = applyEvent(s, event);
    }
    _pendingEvents.clear();
    return s;
  }
}
