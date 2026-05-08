import 'package:meta/meta.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Handle for an active LLM run.
///
/// Returned by [AgentLlmProvider.startRun]. The [events] stream yields
/// [DecodeOutcome]s — `DecodedEvent` for structurally-valid AG-UI events
/// and `DecodeFailed` for payloads the live decoder couldn't parse.
/// Backends that synthesize events in-process emit only `DecodedEvent`s;
/// the AG-UI backend can emit either as it parses the SSE stream.
@immutable
class LlmRunHandle {
  /// Creates an [LlmRunHandle].
  const LlmRunHandle({required this.runId, required this.events});

  /// Unique identifier for this run.
  final String runId;

  /// Stream of decode outcomes for the run.
  ///
  /// `DecodedEvent` arrivals terminate with `RunFinishedEvent` on success
  /// or `RunErrorEvent` on failure. The stream may also end without a
  /// terminal event (network loss), which `RunOrchestrator` handles as a
  /// failure. `DecodeFailed` arrivals surface as drop tiles in the
  /// conversation; the run continues processing subsequent events.
  final Stream<DecodeOutcome> events;
}

/// Contract for backends that can drive agent runs.
///
/// Two construction paths:
/// - **AG-UI backend:** `AgUiLlmProvider` wraps `SoliplexApi` +
///   `AgUiStreamClient` for SSE-driven runs.
/// - **Direct SDK:** providers wrapping `soliplex_completions`
///   synthesize AG-UI events from LLM responses in-process.
///
/// `RunOrchestrator` depends only on this interface, decoupling it from
/// any specific backend.
abstract interface class AgentLlmProvider {
  /// Start a new run (or resume with [existingRunId]) and return the
  /// event stream.
  ///
  /// The provider handles run creation internally. The returned
  /// `LlmRunHandle.events` stream yields `DecodeOutcome`s that
  /// `RunOrchestrator` projects into conversation state.
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
