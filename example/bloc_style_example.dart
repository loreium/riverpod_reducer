/// Bloc Style — all logic flows through events.
///
/// Named methods forward to [dispatch]. Side effects live in [applyEvent].
/// The UI calls methods; [applyEvent] handles everything.
library;

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_reducer/riverpod_reducer.dart';

// --- State ---

sealed class LoginState {}

class LoginInitial extends LoginState {}

class LoginLoading extends LoginState {}

class LoginSuccess extends LoginState {
  LoginSuccess({required this.token});
  final String token;
}

class LoginFailure extends LoginState {
  LoginFailure({required this.message});
  final String message;
}

// --- Events ---

sealed class LoginEvent {}

class LoginSubmitted extends LoginEvent {
  LoginSubmitted({required this.email, required this.password});
  final String email;
  final String password;
}

class LoginReset extends LoginEvent {}

// --- Notifier ---

class LoginNotifier extends ReducerNotifier<LoginState, LoginEvent> {
  @override
  LoginState initialState() => LoginInitial();

  @override
  Future<LoginState> applyEvent(LoginState state, LoginEvent event) async {
    if (event is LoginSubmitted) {
      // Emit intermediate loading state
      this.state = LoginLoading();

      try {
        // Simulate API call
        await Future<void>.delayed(Duration(seconds: 1));

        if (event.email == 'user@example.com' &&
            event.password == 'password123') {
          return LoginSuccess(token: 'jwt-token-abc');
        }
        return LoginFailure(message: 'Invalid credentials');
      } catch (e) {
        return LoginFailure(message: e.toString());
      }
    }

    return reduce(state, event);
  }

  @override
  LoginState reduce(LoginState state, LoginEvent event) => switch (event) {
    LoginSubmitted() => state, // handled in applyEvent
    LoginReset() => LoginInitial(),
  };

  /// Re-expose [dispatch] as public for bloc-style event dispatch.
  @override
  Future<void> dispatch(LoginEvent event) => super.dispatch(event);
}

// --- Provider ---

final loginProvider = NotifierProvider<LoginNotifier, LoginState>(
  LoginNotifier.new,
);

// --- Usage ---
//
// // In a widget — dispatch events directly:
// ref.read(loginProvider.notifier).dispatch(
//   LoginSubmitted(email: 'user@example.com', password: 'password123'),
// );
//
// // Watch state:
// final state = ref.watch(loginProvider);
// switch (state) {
//   LoginInitial() => showLoginForm(),
//   LoginLoading() => showSpinner(),
//   LoginSuccess(:final token) => navigateToHome(token),
//   LoginFailure(:final message) => showError(message),
// }
