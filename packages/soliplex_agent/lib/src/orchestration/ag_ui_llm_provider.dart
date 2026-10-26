import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// AG-UI backend adapter implementing [AgentLlmProvider].
///
/// Wraps [SoliplexApi] (run creation) and [AgUiStreamClient] (SSE streaming)
/// into the [AgentLlmProvider] contract.
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
    String? parentRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    final runId = existingRunId ?? await _createRun(key, parentRunId);
    final updatedInput = SimpleRunAgentInput(
      threadId: input.threadId,
      runId: runId,
      messages: input.messages,
      tools: input.tools,
      state: input.state,
      forwardedProps: input.forwardedProps,
    );
    final events = _agUiStreamClient.runAgent(
      _endpoint(key, runId),
      updatedInput,
      cancelToken: cancelToken,
      onReconnectStatus: onReconnectStatus,
    );
    return LlmRunHandle(runId: runId, events: events);
  }

  @override
  LlmRunHandle followRun({
    required ThreadKey key,
    required String runId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) {
    final events = _agUiStreamClient.followRun(
      _endpoint(key, runId),
      runId,
      cancelToken: cancelToken,
      onReconnectStatus: onReconnectStatus,
    );
    return LlmRunHandle(runId: runId, events: events);
  }

  String _endpoint(ThreadKey key, String runId) =>
      'rooms/${key.roomId}/agui/${key.threadId}/$runId';

  Future<String> _createRun(ThreadKey key, String? parentRunId) async {
    final runInfo = await _api.createRun(
      key.roomId,
      key.threadId,
      parentRunId: parentRunId,
    );
    return runInfo.id;
  }
}
