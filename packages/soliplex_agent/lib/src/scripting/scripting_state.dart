/// Lifecycle state of a session-scoped scripting interpreter.
///
/// Exposed as a reactive signal on `ScriptEnvironment` so that Flutter UI
/// can reactively show "Python running" indicators without polling.
///
/// Maps from the interpreter-specific lifecycle (e.g.,
/// `dart_monty.MontyLifecycleState`) at the implementation layer.
/// Keeping this enum in `soliplex_agent` avoids importing `dart_monty`
/// from the agent package.
enum ScriptingState {
  /// The interpreter is loaded and waiting for the next execution.
  idle,

  /// A script is currently executing.
  executing,

  /// The interpreter has been disposed and cannot accept new executions.
  disposed,
}
