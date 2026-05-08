import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  const key = (serverId: 'server', roomId: 'room', threadId: 'thread');

  group('StreamingLlmProvider', () {
    test(
      'emits RunStarted, text events, RunFinished for text stream',
      () async {
        final provider = StreamingLlmProvider(
          chatFn: ({
            required messages,
            tools,
            systemPrompt,
            maxTokens,
            abortTrigger,
          }) async* {
            yield const LlmTextDelta('Hello');
            yield const LlmTextDelta(' world');
            yield const LlmTextDone('Hello world');
            yield const LlmDone();
          },
        );

        final handle = await provider.startRun(
          key: key,
          input: const SimpleRunAgentInput(
            messages: [UserMessage(id: 'u1', content: 'Hi')],
          ),
        );

        final events = await _decodedEvents(handle);

        expect(events[0], isA<RunStartedEvent>());
        expect(events[1], isA<TextMessageStartEvent>());
        expect(events[2], isA<TextMessageContentEvent>());
        expect((events[2] as TextMessageContentEvent).delta, 'Hello');
        expect(events[3], isA<TextMessageContentEvent>());
        expect((events[3] as TextMessageContentEvent).delta, ' world');
        expect(events[4], isA<TextMessageEndEvent>());
        expect(events[5], isA<RunFinishedEvent>());
      },
    );

    test('emits tool call events', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          yield const LlmToolCallStart(
            callId: 'call_1',
            name: 'execute_python',
          );
          yield const LlmToolCallArgsDelta(
            callId: 'call_1',
            delta: '{"code": "print(42)"}',
          );
          yield const LlmToolCallDone(
            callId: 'call_1',
            arguments: '{"code": "print(42)"}',
          );
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Run code')],
          tools: [
            Tool(name: 'execute_python', description: 'Execute Python code'),
          ],
        ),
      );

      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<ToolCallStartEvent>());
      expect((events[1] as ToolCallStartEvent).toolCallName, 'execute_python');
      expect(events[2], isA<ToolCallArgsEvent>());
      expect(events[3], isA<ToolCallEndEvent>());
      expect(events[4], isA<RunFinishedEvent>());
    });

    test('closes text message before tool call', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          yield const LlmTextDelta('Thinking...');
          yield const LlmToolCallStart(callId: 'c1', name: 'search');
          yield const LlmToolCallArgsDelta(callId: 'c1', delta: '{}');
          yield const LlmToolCallDone(callId: 'c1', arguments: '{}');
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );

      final events = await _decodedEvents(handle);

      // RunStarted, TextStart, TextContent, TextEnd, ToolStart, ToolArgs,
      // ToolEnd, RunFinished
      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<TextMessageStartEvent>());
      expect(events[2], isA<TextMessageContentEvent>());
      expect(events[3], isA<TextMessageEndEvent>());
      expect(events[4], isA<ToolCallStartEvent>());
    });

    test('emits RunErrorEvent on LlmError', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          yield const LlmError('connection refused');
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );

      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<RunErrorEvent>());
      expect((events[1] as RunErrorEvent).message, 'connection refused');
    });

    test('catches exceptions from chatFn and emits RunErrorEvent', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          throw Exception('network error');
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );

      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<RunErrorEvent>());
      expect((events[1] as RunErrorEvent).message, contains('network error'));
    });

    test('synthesizes RunFinished when stream ends without LlmDone', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          yield const LlmTextDelta('Hello');
          // Stream ends without LlmDone
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );

      final events = await _decodedEvents(handle);

      // Should synthesize TextEnd and RunFinished
      expect(events.last, isA<RunFinishedEvent>());
      expect(events[events.length - 2], isA<TextMessageEndEvent>());
    });

    test('passes system prompt to chatFn', () async {
      String? receivedPrompt;
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          receivedPrompt = systemPrompt;
          yield const LlmDone();
        },
        systemPrompt: 'You are a helpful assistant.',
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
      );

      await handle.events.drain<void>();
      expect(receivedPrompt, 'You are a helpful assistant.');
    });

    test('converts AG-UI messages to LlmChatMessage correctly', () async {
      List<LlmChatMessage>? receivedMessages;
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          receivedMessages = messages;
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [
            SystemMessage(id: 's1', content: 'Be helpful'),
            UserMessage(id: 'u1', content: 'Hello'),
            AssistantMessage(
              id: 'a1',
              content: 'I will search',
              toolCalls: [
                ToolCall(
                  id: 'tc_1',
                  function: FunctionCall(
                    name: 'search',
                    arguments: '{"q": "dart"}',
                  ),
                ),
              ],
            ),
            ToolMessage(
              id: 't1',
              toolCallId: 'tc_1',
              content: 'Found 5 results',
            ),
          ],
        ),
      );

      await handle.events.drain<void>();

      expect(receivedMessages, hasLength(4));
      expect(receivedMessages![0], isA<LlmSystemMessage>());
      expect((receivedMessages![0] as LlmSystemMessage).content, 'Be helpful');
      expect(receivedMessages![1], isA<LlmUserMessage>());
      expect(receivedMessages![2], isA<LlmAssistantMessage>());
      final assistant = receivedMessages![2] as LlmAssistantMessage;
      expect(assistant.content, 'I will search');
      expect(assistant.toolCalls, hasLength(1));
      expect(assistant.toolCalls!.first.name, 'search');
      expect(receivedMessages![3], isA<LlmToolResultMessage>());
      final toolResult = receivedMessages![3] as LlmToolResultMessage;
      expect(toolResult.callId, 'tc_1');
      expect(toolResult.output, 'Found 5 results');
    });

    test('converts AG-UI tools to LlmToolDef correctly', () async {
      List<LlmToolDef>? receivedTools;
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          receivedTools = tools;
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
          tools: [
            Tool(
              name: 'execute_python',
              description: 'Execute Python code',
              parameters: {
                'type': 'object',
                'properties': {
                  'code': {'type': 'string'},
                },
              },
            ),
          ],
        ),
      );

      await handle.events.drain<void>();

      expect(receivedTools, hasLength(1));
      expect(receivedTools!.first.name, 'execute_python');
      expect(receivedTools!.first.description, 'Execute Python code');
      expect(receivedTools!.first.parameters, isNotNull);
    });

    test('respects cancellation', () async {
      final token = CancelToken();
      var deltaCount = 0;

      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          for (var i = 0; i < 100; i++) {
            yield LlmTextDelta('chunk $i ');
            // Simulate async delay to allow cancellation to propagate.
            await Future<void>.delayed(Duration.zero);
          }
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
        cancelToken: token,
      );

      await for (final outcome in handle.events) {
        final event = (outcome as DecodedEvent).event;
        if (event is TextMessageContentEvent) {
          deltaCount++;
          if (deltaCount >= 3) {
            token.cancel();
          }
        }
      }

      // Should have stopped early due to cancellation.
      expect(deltaCount, lessThan(100));
    });

    test('uses existingRunId when provided', () async {
      final provider = StreamingLlmProvider(
        chatFn: ({
          required messages,
          tools,
          systemPrompt,
          maxTokens,
          abortTrigger,
        }) async* {
          yield const LlmDone();
        },
      );

      final handle = await provider.startRun(
        key: key,
        input: const SimpleRunAgentInput(
          messages: [UserMessage(id: 'u1', content: 'Hi')],
        ),
        existingRunId: 'existing-123',
      );

      expect(handle.runId, 'existing-123');
    });
  });
}

Future<List<BaseEvent>> _decodedEvents(LlmRunHandle handle) async =>
    (await handle.events.toList())
        .whereType<DecodedEvent>()
        .map((d) => d.event)
        .toList();
