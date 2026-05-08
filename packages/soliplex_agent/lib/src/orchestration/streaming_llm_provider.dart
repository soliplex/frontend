import 'dart:async';

import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Callback type for streaming LLM chat with tool support.
///
/// Wraps `OpenResponsesLlmProvider.chatStream`. The app layer
/// passes this in; `soliplex_agent` never imports `open_responses`.
typedef StreamingChatFn = Stream<LlmEvent> Function({
  required List<LlmChatMessage> messages,
  List<LlmToolDef>? tools,
  String? systemPrompt,
  int? maxTokens,
  Future<void>? abortTrigger,
});

/// [AgentLlmProvider] backed by a streaming LLM callback with native
/// tool calling support.
///
/// Maps [LlmEvent] to AG-UI [BaseEvent] in real-time.
/// Replaces `ChatFnLlmProvider` for providers that support streaming
/// and native tool calling (via open_responses).
class StreamingLlmProvider implements AgentLlmProvider {
  /// Creates a [StreamingLlmProvider].
  StreamingLlmProvider({required StreamingChatFn chatFn, this.systemPrompt})
      : _chatFn = chatFn;

  final StreamingChatFn _chatFn;

  /// Optional base system prompt.
  final String? systemPrompt;

  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    final runId =
        existingRunId ?? 'local-${DateTime.now().microsecondsSinceEpoch}';
    final events = _run(key, input, runId, cancelToken);
    return LlmRunHandle(runId: runId, events: events);
  }

  Stream<DecodeOutcome> _run(
    ThreadKey key,
    SimpleRunAgentInput input,
    String runId,
    CancelToken? cancelToken,
  ) async* {
    yield _wrap(RunStartedEvent(threadId: key.threadId, runId: runId));

    if (cancelToken?.isCancelled ?? false) return;

    // Map CancelToken → Future for open_responses abort trigger.
    final abortCompleter = Completer<void>();

    unawaited(
      cancelToken?.whenCancelled.then((_) {
        if (!abortCompleter.isCompleted) abortCompleter.complete();
      }),
    );

    try {
      final messages = _convertMessages(input);
      final tools = _convertTools(input.tools);

      String? currentMsgId;

      await for (final event in _chatFn(
        messages: messages,
        tools: tools,
        systemPrompt: systemPrompt,
        abortTrigger: abortCompleter.future,
      )) {
        if (cancelToken?.isCancelled ?? false) return;

        switch (event) {
          case LlmTextDelta(:final text):
            if (currentMsgId == null) {
              final msgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
              currentMsgId = msgId;
              yield _wrap(TextMessageStartEvent(messageId: msgId));
            }
            yield _wrap(
              TextMessageContentEvent(messageId: currentMsgId, delta: text),
            );

          case LlmTextDone():
            if (currentMsgId case final msgId?) {
              yield _wrap(TextMessageEndEvent(messageId: msgId));
              currentMsgId = null;
            }

          case LlmToolCallStart(:final callId, :final name):
            // Close any open text message first.
            if (currentMsgId case final msgId?) {
              yield _wrap(TextMessageEndEvent(messageId: msgId));
              currentMsgId = null;
            }
            yield _wrap(
              ToolCallStartEvent(toolCallId: callId, toolCallName: name),
            );

          case LlmToolCallArgsDelta(:final callId, :final delta):
            yield _wrap(ToolCallArgsEvent(toolCallId: callId, delta: delta));

          case LlmToolCallDone(:final callId):
            yield _wrap(ToolCallEndEvent(toolCallId: callId));

          case LlmDone():
            if (currentMsgId case final msgId?) {
              yield _wrap(TextMessageEndEvent(messageId: msgId));
            }
            yield _wrap(RunFinishedEvent(threadId: key.threadId, runId: runId));
            return;

          case LlmError(:final message):
            yield _wrap(RunErrorEvent(message: message));
            return;
        }
      }

      // Stream ended without explicit done — synthesize finish.
      if (currentMsgId case final msgId?) {
        yield _wrap(TextMessageEndEvent(messageId: msgId));
      }
      yield _wrap(RunFinishedEvent(threadId: key.threadId, runId: runId));
    } on CancelledException {
      // Surface cancels as a stream error so the orchestrator routes
      // them to `CancelledState` via `_onStreamError`. Yielding a
      // `RunErrorEvent` would land in `FailedState(serverError)` with
      // the runtime-type stringified into the user-facing message.
      rethrow;
    } on Object catch (e) {
      final msg = e is SoliplexException ? e.message : e.toString();
      yield _wrap(RunErrorEvent(message: msg));
    }
  }

  /// `rawJson` is `const {}` because synthesized events have no source
  /// JSON; if `processEvent` ever throws on one, the resulting drop tile
  /// will carry an empty payload.
  static DecodedEvent _wrap(BaseEvent event) => DecodedEvent(event, const {});

  List<LlmChatMessage> _convertMessages(SimpleRunAgentInput input) {
    final result = <LlmChatMessage>[];
    final messages = input.messages;
    if (messages == null) return result;
    for (final msg in messages) {
      switch (msg) {
        case final UserMessage m:
          result.add(LlmUserMessage(m.content));
        case final AssistantMessage m:
          final tcs = m.toolCalls
              ?.map(
                (tc) => LlmToolCall(
                  id: tc.id,
                  name: tc.function.name,
                  arguments: tc.function.arguments,
                ),
              )
              .toList();
          result.add(LlmAssistantMessage(content: m.content, toolCalls: tcs));
        case final ToolMessage m:
          result.add(
            LlmToolResultMessage(callId: m.toolCallId, output: m.content),
          );
        case final SystemMessage m:
          result.add(LlmSystemMessage(m.content));
        default:
          break;
      }
    }
    return result;
  }

  List<LlmToolDef>? _convertTools(List<Tool>? tools) {
    if (tools == null || tools.isEmpty) return null;
    return tools
        .map(
          (t) => LlmToolDef(
            name: t.name,
            description: t.description,
            parameters: t.parameters as Map<String, dynamic>?,
          ),
        )
        .toList();
  }
}
