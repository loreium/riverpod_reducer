## 0.2.0

- **BREAKING:** `applyEvent()` renamed to `middleware()` and now returns `Future<E?>` instead of `Future<S>`.
  - Return the event (or a modified event) to pass it to `reduce()`.
  - Return `null` to drop/block the event.
  - Middleware no longer mutates state directly — all state transitions flow through `reduce()`.
- Removed bloc-style pattern (side effects in `applyEvent`). Use named methods with `dispatch()` for async workflows.

## 0.1.0

- Initial release.
- `ReducerNotifier<S, E>` base class with queued initialization pattern.
- `bind()` and `bindAsync()` for reactive dependency bindings.
- `applyEvent()` middleware hook for logging and event interception.
- Pure `reduce()` function for testable state transitions.
