import 'dart:async';
import 'dart:convert';

import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_agent/src/orchestration/tool_call_parser.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Callback type for LLM chat.
///
/// Accepts a list of messages and optional system prompt.
/// Returns the LLM's text response.
///
/// This typedef avoids a dependency on `soliplex_completions` in
/// `soliplex_agent`. The application layer bridges:
/// ```dart
/// final ollama = OllamaLlmProvider(model: 'qwen3:8b');
/// final provider = ChatFnLlmProvider(
///   chatFn: (msgs, {systemPrompt, maxTokens}) =>
///       ollama.chat(msgs, systemPrompt: systemPrompt, maxTokens: maxTokens),
/// );
/// ```
typedef ChatFn = Future<String> Function(
  List<({String role, String content})> messages, {
  String? systemPrompt,
  int? maxTokens,
});

/// [AgentLlmProvider] backed by a [ChatFn] callback.
///
/// Wraps a [ChatFn] callback, converts AG-UI messages to simple
/// role/content pairs, and synthesizes AG-UI events from the LLM's
/// text response. Tool calling uses a text-based protocol (Phase 1)
/// — the system prompt instructs the LLM to emit fenced `tool_call`
/// blocks that [parseToolCallResponse] extracts.
class ChatFnLlmProvider implements AgentLlmProvider {
  /// Creates a [ChatFnLlmProvider].
  ///
  /// [chatFn] is the LLM chat callback.
  /// [systemPrompt] is an optional base system prompt prepended to
  /// the tool instructions.
  ChatFnLlmProvider({required ChatFn chatFn, this.systemPrompt})
      : _chatFn = chatFn;

  final ChatFn _chatFn;

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

  Stream<BaseEvent> _run(
    ThreadKey key,
    SimpleRunAgentInput input,
    String runId,
    CancelToken? cancelToken,
  ) async* {
    yield RunStartedEvent(threadId: key.threadId, runId: runId);

    if (cancelToken?.isCancelled ?? false) return;

    try {
      final messages = _convertMessages(input);
      final fullSystemPrompt = _buildSystemPrompt(input.tools);

      if (cancelToken?.isCancelled ?? false) return;

      final response = await _chatFn(messages, systemPrompt: fullSystemPrompt);

      if (cancelToken?.isCancelled ?? false) return;

      final parsed = parseToolCallResponse(response);

      switch (parsed) {
        case TextResponse(:final text):
          final msgId = 'msg-${DateTime.now().microsecondsSinceEpoch}';
          yield TextMessageStartEvent(messageId: msgId);
          yield TextMessageContentEvent(messageId: msgId, delta: text);
          yield TextMessageEndEvent(messageId: msgId);

        case ToolCallResponse(:final prefixText, :final name, :final arguments):
          if (prefixText.isNotEmpty) {
            final textMsgId =
                'msg-text-${DateTime.now().microsecondsSinceEpoch}';
            yield TextMessageStartEvent(messageId: textMsgId);
            yield TextMessageContentEvent(
              messageId: textMsgId,
              delta: prefixText,
            );
            yield TextMessageEndEvent(messageId: textMsgId);
          }
          final tcId = 'tc-${DateTime.now().microsecondsSinceEpoch}';
          yield ToolCallStartEvent(toolCallId: tcId, toolCallName: name);
          yield ToolCallArgsEvent(
            toolCallId: tcId,
            delta: jsonEncode(arguments),
          );
          yield ToolCallEndEvent(toolCallId: tcId);
      }

      yield RunFinishedEvent(threadId: key.threadId, runId: runId);
    } on CancelledException {
      // Surface cancels as a stream error so the orchestrator routes
      // them to `CancelledState` via `_onStreamError`. Yielding a
      // `RunErrorEvent` would land in `FailedState(serverError)` with
      // the runtime-type stringified into the user-facing message.
      rethrow;
    } on Object catch (e) {
      yield RunErrorEvent(message: e.toString());
    }
  }

  /// Converts AG-UI messages to simple role/content pairs for the
  /// [ChatFn].
  List<({String role, String content})> _convertMessages(
    SimpleRunAgentInput input,
  ) {
    final result = <({String role, String content})>[];
    final messages = input.messages;
    if (messages == null) return result;
    for (final msg in messages) {
      switch (msg) {
        case final UserMessage m:
          result.add((role: 'user', content: m.content));
        case final AssistantMessage m:
          final toolCalls = m.toolCalls;
          if (toolCalls != null && toolCalls.isNotEmpty) {
            final tc = toolCalls.first;
            result.add(
              (
                role: 'assistant',
                content: "[Called tool '${tc.function.name}' with arguments: "
                    '${tc.function.arguments}]',
              ),
            );
          } else {
            result.add((role: 'assistant', content: m.content ?? ''));
          }
        case final ToolMessage m:
          result.add(
            (
              role: 'user',
              content: "[Tool result for '${m.toolCallId}']: ${m.content}",
            ),
          );
        case final SystemMessage m:
          result.add(
            (role: 'system', content: m.content),
          );
        default:
          break;
      }
    }
    return result;
  }

  /// Builds the full system prompt including tool definitions and
  /// call format instructions.
  String _buildSystemPrompt(List<Tool>? tools) {
    final buffer = StringBuffer();
    if (systemPrompt != null) {
      buffer
        ..writeln(systemPrompt)
        ..writeln();
    }

    if (tools != null && tools.isNotEmpty) {
      buffer
        ..writeln('## Available Tools')
        ..writeln();
      for (final tool in tools) {
        buffer.writeln('### ${tool.name}');
        if (tool.description.isNotEmpty) {
          buffer.writeln('Description: ${tool.description}');
        }
        if (tool.parameters != null) {
          buffer.writeln('Parameters: ${jsonEncode(tool.parameters)}');
        }
        buffer.writeln();
      }
      buffer
        ..writeln('## How to Call Tools')
        ..writeln()
        ..writeln(
          'When you need to use a tool, respond with EXACTLY this format:',
        )
        ..writeln('```tool_call')
        ..writeln('{"name": "tool_name", "arguments": {"param1": "value"}}')
        ..writeln('```')
        ..writeln()
        ..writeln(
          'Only call ONE tool at a time. Do not include other text with a '
          'tool call.',
        )
        ..writeln(
          "If you don't need to call a tool, respond normally with text.",
        );
    }

    return buffer.toString().trimRight();
  }
}
