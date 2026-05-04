import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// AG-UI backend adapter implementing [AgentLlmProvider].
///
/// Wraps [SoliplexApi] (run creation) and [AgUiStreamClient] (SSE streaming)
/// into the unified [AgentLlmProvider] contract. Zero behavior change from
/// the pre-Phase 3 wiring — this is a mechanical extraction.
class AgUiLlmProvider implements AgentLlmProvider {
  /// Creates an [AgUiLlmProvider] from existing AG-UI clients.
  const AgUiLlmProvider({
    required SoliplexApi api,
    required AgUiStreamClient agUiStreamClient,
  })  : _api = api,
        _agUiStreamClient = agUiStreamClient;

  final SoliplexApi _api;
  final AgUiStreamClient _agUiStreamClient;

  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    final runId = existingRunId ?? await _createRun(key);
    final updatedInput = SimpleRunAgentInput(
      threadId: input.threadId,
      runId: runId,
      messages: input.messages,
      tools: input.tools,
      state: input.state,
    );
    final endpoint = 'rooms/${key.roomId}/agui/${key.threadId}/$runId';
    final events = _agUiStreamClient.runAgent(
      endpoint,
      updatedInput,
      cancelToken: cancelToken,
      onReconnectStatus: onReconnectStatus,
    );
    return LlmRunHandle(runId: runId, events: events);
  }

  Future<String> _createRun(ThreadKey key) async {
    final runInfo = await _api.createRun(key.roomId, key.threadId);
    return runInfo.id;
  }
}
