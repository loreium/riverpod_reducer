import 'dart:async';

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
  Future<void>? _queue;
  int _generation = 0;

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
  /// conditional event handling, or **async side effects**.
  ///
  /// Default implementation delegates to [reduce].
  ///
  /// Events are processed sequentially — subsequent [dispatch] calls queue
  /// until the current event completes.
  /// Use `this.state = ...` to emit intermediate states during async work.
  ///
  /// During [build], pending events from [bind]/[bindAsync] are folded
  /// through [reduce] directly, bypassing this hook.
  ///
  /// ```dart
  /// @override
  /// Future<MyState> applyEvent(MyState state, MyEvent event) async {
  ///   if (event is SubmitForm) {
  ///     this.state = state.copyWith(isLoading: true);
  ///     await api.submit(state.data);
  ///     return state.copyWith(isLoading: false);
  ///   }
  ///   return reduce(state, event);
  /// }
  /// ```
  @protected
  Future<S> applyEvent(S state, E event) async => reduce(state, event);

  /// Dispatches an [event], triggering [applyEvent] → [reduce].
  ///
  /// This method is `@protected` — call it from within public methods on
  /// your notifier, not directly from widgets:
  ///
  /// ```dart
  /// // Cubit style — side effects in the method:
  /// Future<void> submit() async {
  ///   await dispatch(SubmitStarted());
  ///   try {
  ///     await api.submit(state.data);
  ///     await dispatch(SubmitSucceeded());
  ///   } catch (e) {
  ///     await dispatch(SubmitFailed(e.toString()));
  ///   }
  /// }
  ///
  /// // Bloc style — re-expose dispatch as public:
  /// @override
  /// Future<void> dispatch(MyEvent event) => super.dispatch(event);
  /// ```
  ///
  /// During initialization (inside [build]), events are queued and folded
  /// through [reduce] after [bindings] completes.
  ///
  /// After initialization, events are processed sequentially — if a previous
  /// event is still being handled, the new event queues behind it.
  @protected
  @visibleForTesting
  Future<void> dispatch(E event) {
    if (_initializing) {
      _pendingEvents.add(event);
      return Future.value();
    }

    final prev = _queue;
    final future =
        prev != null
            ? prev.catchError((_) {}).then((_) => _processEvent(event))
            : _processEvent(event);

    _queue = future;
    // Clear the queue when this future completes, but only if no new events
    // were chained onto it in the meantime (which would have replaced _queue
    // with a different future).
    future.then(
      (_) {
        if (identical(_queue, future)) _queue = null;
      },
      onError: (_) {
        if (identical(_queue, future)) _queue = null;
      },
    );
    return future;
  }

  Future<void> _processEvent(E event) async {
    final gen = _generation;
    final next = await applyEvent(state, event);
    if (gen != _generation) return; // stale after rebuild, discard
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
  /// [reduce] to produce the final initial state.
  ///
  /// **Do not override.** Implement [initialState] and [bindings] instead.
  @override
  @nonVirtual
  S build() {
    _generation++;
    _initializing = true;
    _pendingEvents.clear();
    _queue = null;
    final initial = initialState();
    bindings();
    _initializing = false;
    var s = initial;
    for (final event in _pendingEvents) {
      s = reduce(s, event);
    }
    _pendingEvents.clear();
    return s;
  }
}
