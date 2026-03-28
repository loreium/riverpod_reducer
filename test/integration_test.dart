import 'package:riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Pumps the event loop so async dispatches from bindings complete.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('integration', () {
    test('full lifecycle: init → bind → dispatch → state', () async {
      final container = createContainer();

      // Build: initialState + bindings(bind externalCountProvider=10)
      final state = container.read(boundProvider);
      expect(state.externalCount, 10);
      expect(state.internalCount, 0);

      // User dispatch
      await container
          .read(boundProvider.notifier)
          .dispatch(InternalIncrement());
      expect(container.read(boundProvider).internalCount, 1);

      // External dependency change
      container.read(externalCountProvider.notifier).state = 20;
      await pump();
      final updated = container.read(boundProvider);
      expect(updated.externalCount, 20);
      expect(updated.internalCount, 1); // preserved
    });

    test('notifier with overridden initial dependency', () {
      final container = createContainer(
        overrides: [externalCountProvider.overrideWith((ref) => 999)],
      );

      final state = container.read(boundProvider);
      expect(state.externalCount, 999);
    });

    test('auto-dispose notifier works', () async {
      final autoProvider = NotifierProvider.autoDispose<CounterNotifier, int>(
        CounterNotifier.new,
      );

      final container = createContainer();
      final sub = container.listen(autoProvider, (_, _) {});

      await container.read(autoProvider.notifier).dispatch(Increment());
      expect(container.read(autoProvider), 1);

      sub.close();
      // After closing subscription, auto-dispose may clean up
      // (Riverpod internal behavior — just verify it doesn't throw)
    });

    test('realistic form notifier scenario', () async {
      final userProvider = StateProvider<String>((ref) => 'Alice');

      final formProvider = NotifierProvider<_FormNotifier, _FormState>(
        () => _FormNotifier(userProvider),
      );

      final container = createContainer();
      final state = container.read(formProvider);
      expect(state.userName, 'Alice');
      expect(state.email, '');
      expect(state.isSubmitting, false);

      // User types email
      await container
          .read(formProvider.notifier)
          .dispatch(_EmailChanged('a@b.com'));
      expect(container.read(formProvider).email, 'a@b.com');

      // External user changes
      container.read(userProvider.notifier).state = 'Bob';
      await pump();
      expect(container.read(formProvider).userName, 'Bob');
      expect(container.read(formProvider).email, 'a@b.com'); // preserved

      // Submit flow
      await container.read(formProvider.notifier).dispatch(_SubmitStarted());
      expect(container.read(formProvider).isSubmitting, true);

      await container.read(formProvider.notifier).dispatch(_SubmitSucceeded());
      expect(container.read(formProvider).isSubmitting, false);
      expect(container.read(formProvider).error, isNull);
    });
  });
}

// --- Form notifier for integration test ---

class _FormState {
  _FormState({
    required this.userName,
    required this.email,
    required this.isSubmitting,
    this.error,
  });

  final String userName;
  final String email;
  final bool isSubmitting;
  final String? error;

  _FormState copyWith({
    String? userName,
    String? email,
    bool? isSubmitting,
    String? Function()? error,
  }) => _FormState(
    userName: userName ?? this.userName,
    email: email ?? this.email,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error != null ? error() : this.error,
  );
}

sealed class _FormEvent {}

class _UserChanged extends _FormEvent {
  _UserChanged(this.name);
  final String name;
}

class _EmailChanged extends _FormEvent {
  _EmailChanged(this.email);
  final String email;
}

class _SubmitStarted extends _FormEvent {}

class _SubmitSucceeded extends _FormEvent {}

class _SubmitFailed extends _FormEvent {
  _SubmitFailed(this.message);
  final String message;
}

class _FormNotifier extends ReducerNotifier<_FormState, _FormEvent> {
  _FormNotifier(this._userProvider);
  final StateProvider<String> _userProvider;

  @override
  _FormState initialState() =>
      _FormState(userName: '', email: '', isSubmitting: false);

  @override
  void bindings() {
    bind<String>(_userProvider, (_, name) => _UserChanged(name));
  }

  @override
  _FormState reduce(_FormState state, _FormEvent event) => switch (event) {
    _UserChanged(:final name) => state.copyWith(userName: name),
    _EmailChanged(:final email) => state.copyWith(email: email),
    _SubmitStarted() => state.copyWith(isSubmitting: true, error: () => null),
    _SubmitSucceeded() => state.copyWith(isSubmitting: false),
    _SubmitFailed(:final message) => state.copyWith(
      isSubmitting: false,
      error: () => message,
    ),
  };
}
