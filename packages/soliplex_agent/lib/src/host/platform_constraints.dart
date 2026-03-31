/// Platform-level capability flags.
///
/// Allows agent orchestration and the Monty bridge to adapt behavior
/// based on runtime constraints. Global per app instance, not per session.
abstract interface class PlatformConstraints {
  /// Whether the platform supports parallel Python interpreters.
  ///
  /// Native (Isolate): true. Web (WASM singleton): false.
  bool get supportsParallelExecution;

  /// Whether the Monty runtime supports async/futures mode.
  ///
  /// WASM: false (sync-only start/resume loop).
  /// Native: false today, potentially true when MontyResolveFutures lands.
  bool get supportsAsyncMode;

  /// Max concurrent Monty bridges before serialization is required.
  ///
  /// Native: high (one Isolate each). Web: 1 (mutex-serialized).
  int get maxConcurrentBridges;

  /// Whether the interpreter can be re-entered while suspended.
  ///
  /// Native (Isolate): true — each bridge has its own interpreter.
  /// Web (WASM): false — single interpreter, non-reentrant.
  bool get supportsReentrantInterpreter;

  /// Max concurrent agent sessions (HTTP streams + tool execution).
  ///
  /// Independent of [maxConcurrentBridges], which controls local
  /// interpreter access. Sessions that only stream AG-UI over HTTP/SSE
  /// can safely run at this limit even on WASM, where the event loop
  /// interleaves I/O-bound work without contention.
  ///
  /// Native/Mobile: typically matches [maxConcurrentBridges].
  /// Web: can be higher because HTTP streams don't need the interpreter.
  int get maxConcurrentSessions;
}
