import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Handle for an active LLM run.
///
/// Returned by [AgentLlmProvider.startRun]. The [events] stream yields
/// AG-UI `BaseEvent`s regardless of the underlying backend — backend
/// implementations emit events natively, while direct-SDK implementations
/// synthesize them from LLM responses.
@immutable
class LlmRunHandle {
  /// Creates an [LlmRunHandle].
  const LlmRunHandle({required this.runId, required this.events});

  /// Unique identifier for this run.
  final String runId;

  /// Stream of AG-UI events for the run.
  ///
  /// Terminates with `RunFinishedEvent` on success or `RunErrorEvent` on
  /// failure. The stream may also end without a terminal event (network
  /// loss), which `RunOrchestrator` handles as a failure.
  final Stream<BaseEvent> events;
}

/// Contract for backends that can drive agent runs.
///
/// Two construction paths:
/// - **AG-UI backend:** `AgUiLlmProvider` wraps `SoliplexApi` +
///   `AgUiStreamClient` — the existing backend path.
/// - **Direct SDK:** A future provider wrapping `soliplex_completions`
///   providers, synthesizing AG-UI events from LLM responses.
///
/// `RunOrchestrator` depends only on this interface, decoupling it from
/// any specific backend.
abstract interface class AgentLlmProvider {
  /// Start a new run (or resume with [existingRunId]) and return the
  /// event stream.
  ///
  /// The provider handles run creation internally. The returned
  /// `LlmRunHandle.events` stream yields `BaseEvent`s that
  /// `RunOrchestrator` processes via the existing event pipeline.
  ///
  /// [onReconnectStatus] receives SSE reconnect lifecycle updates from
  /// the AG-UI backend (the only provider that can drop and resume
  /// mid-run). Other providers ignore the callback. Optional — null
  /// means no reconnect surfacing.
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  });
}
