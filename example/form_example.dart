import 'package:riverpod/legacy.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- State ---

class FormState {
  FormState({
    required this.userName,
    required this.email,
    required this.isSubmitting,
    this.error,
  });

  final String userName;
  final String email;
  final bool isSubmitting;
  final String? error;

  FormState copyWith({
    String? userName,
    String? email,
    bool? isSubmitting,
    String? Function()? error,
  }) => FormState(
    userName: userName ?? this.userName,
    email: email ?? this.email,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    error: error != null ? error() : this.error,
  );

  @override
  String toString() =>
      'FormState(user: $userName, email: $email, submitting: $isSubmitting, error: $error)';
}

// --- Events ---

sealed class FormEvent {}

class UserChanged extends FormEvent {
  UserChanged(this.name);
  final String name;
}

class EmailChanged extends FormEvent {
  EmailChanged(this.email);
  final String email;
}

class SubmitStarted extends FormEvent {}

class SubmitSucceeded extends FormEvent {}

class SubmitFailed extends FormEvent {
  SubmitFailed(this.message);
  final String message;
}

// --- External dependency ---

final currentUserProvider = StateProvider<String>((ref) => 'Alice');

// --- Notifier ---

class FormNotifier extends ReducerNotifier<FormState, FormEvent> {
  @override
  FormState initialState() =>
      FormState(userName: '', email: '', isSubmitting: false);

  @override
  void bindings() {
    // External user changes → UserChanged event → reduce updates state
    // Internal state (email, isSubmitting) is preserved.
    bind<String>(currentUserProvider, (_, name) => UserChanged(name));
  }

  @override
  FormState reduce(FormState state, FormEvent event) => switch (event) {
    UserChanged(:final name) => state.copyWith(userName: name),
    EmailChanged(:final email) => state.copyWith(email: email),
    SubmitStarted() => state.copyWith(isSubmitting: true, error: () => null),
    SubmitSucceeded() => state.copyWith(isSubmitting: false),
    SubmitFailed(:final message) => state.copyWith(
      isSubmitting: false,
      error: () => message,
    ),
  };

  void changeEmail(String email) => dispatch(EmailChanged(email));

  /// Side effects live in methods — they dispatch events, not mutate state.
  Future<void> submit() async {
    await dispatch(SubmitStarted());
    try {
      // await ref.read(apiProvider).submitForm(state.email);
      await Future<void>.delayed(Duration(milliseconds: 100)); // simulate API
      await dispatch(SubmitSucceeded());
    } catch (e) {
      await dispatch(SubmitFailed(e.toString()));
    }
  }
}

final formProvider = NotifierProvider<FormNotifier, FormState>(
  FormNotifier.new,
);

// --- Usage ---

void main() async {
  final container = ProviderContainer();
  final notifier = container.read(formProvider.notifier);

  print(container.read(formProvider)); // user: Alice (from binding)

  // User types email — internal state, not affected by external deps
  notifier.changeEmail('alice@example.com');
  print(container.read(formProvider));

  // External user changes — email is preserved!
  container.read(currentUserProvider.notifier).state = 'Bob';
  print(container.read(formProvider)); // user: Bob, email: alice@example.com

  // Submit flow
  await notifier.submit();
  print(container.read(formProvider)); // submitting: false

  container.dispose();
}
