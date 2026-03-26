/// A pure reducer pattern for Riverpod notifiers.
///
/// Separates state initialization from reactive bindings with a single
/// `reduce(State, Event) → State` function.
library;

export 'package:riverpod/misc.dart' show ProviderListenable;
export 'package:riverpod/riverpod.dart'
    show AsyncValue, AsyncData, AsyncError, AsyncLoading;

export 'src/reducer_notifier.dart';
