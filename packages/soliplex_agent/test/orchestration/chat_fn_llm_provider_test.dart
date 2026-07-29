import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('ChatFnLlmProvider', () {
    const key = (serverId: 'local', roomId: 'test-room', threadId: 'thread-1');

    SimpleRunAgentInput input0({List<Message>? messages, List<Tool>? tools}) {
      return SimpleRunAgentInput(
        threadId: key.threadId,
        runId: 'run-1',
        messages: messages ?? [UserMessage(id: 'u1', content: 'Hello')],
        tools: tools,
      );
    }

    test('text response emits correct AG-UI event sequence', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async =>
            'Hello! How can I help?',
      );

      final handle = await provider.startRun(key: key, input: input0());
      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<TextMessageStartEvent>());
      expect(events[2], isA<TextMessageContentEvent>());
      expect(
        (events[2] as TextMessageContentEvent).delta,
        'Hello! How can I help?',
      );
      expect(events[3], isA<TextMessageEndEvent>());
      expect(events[4], isA<RunFinishedEvent>());
      expect(events, hasLength(5));
    });

    test('tool call response emits ToolCall events', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => '''
```tool_call
{"name": "get_weather", "arguments": {"city": "NYC"}}
```''',
      );

      final handle = await provider.startRun(key: key, input: input0());
      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<ToolCallStartEvent>());
      expect((events[1] as ToolCallStartEvent).toolCallName, 'get_weather');
      expect(events[2], isA<ToolCallArgsEvent>());
      expect(events[3], isA<ToolCallEndEvent>());
      expect(events[4], isA<RunFinishedEvent>());
      expect(events, hasLength(5));
    });

    test('tool call with prefix text emits text then tool call', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => '''
Let me check.

```tool_call
{"name": "search", "arguments": {"q": "dart"}}
```''',
      );

      final handle = await provider.startRun(key: key, input: input0());
      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      // Prefix text events.
      expect(events[1], isA<TextMessageStartEvent>());
      expect(events[2], isA<TextMessageContentEvent>());
      expect((events[2] as TextMessageContentEvent).delta, 'Let me check.');
      expect(events[3], isA<TextMessageEndEvent>());
      // Tool call events.
      expect(events[4], isA<ToolCallStartEvent>());
      expect(events[5], isA<ToolCallArgsEvent>());
      expect(events[6], isA<ToolCallEndEvent>());
      expect(events[7], isA<RunFinishedEvent>());
    });

    test('malformed tool call falls back to text response', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => '''
```tool_call
{invalid json}
```''',
      );

      final handle = await provider.startRun(key: key, input: input0());
      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<TextMessageStartEvent>());
      expect(events[2], isA<TextMessageContentEvent>());
      expect(events[3], isA<TextMessageEndEvent>());
      expect(events[4], isA<RunFinishedEvent>());
    });

    test('LLM error emits RunErrorEvent', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async =>
            throw Exception('Connection refused'),
      );

      final handle = await provider.startRun(key: key, input: input0());
      final events = await _decodedEvents(handle);

      expect(events[0], isA<RunStartedEvent>());
      expect(events[1], isA<RunErrorEvent>());
      expect(
        (events[1] as RunErrorEvent).message,
        contains('Connection refused'),
      );
    });

    test('existingRunId is used when provided', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => 'ok',
      );

      final handle = await provider.startRun(
        key: key,
        input: input0(),
        existingRunId: 'my-run-42',
      );

      expect(handle.runId, 'my-run-42');
      final events = await _decodedEvents(handle);
      expect((events[0] as RunStartedEvent).runId, 'my-run-42');
    });

    test('generates local runId when existingRunId is null', () async {
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => 'ok',
      );

      final handle = await provider.startRun(key: key, input: input0());
      expect(handle.runId, startsWith('local-'));
    });

    test('system prompt includes tool definitions', () async {
      String? capturedSystemPrompt;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedSystemPrompt = systemPrompt;
          return 'ok';
        },
        systemPrompt: 'You are helpful.',
      );

      final tools = [
        const Tool(
          name: 'get_weather',
          description: 'Get weather for a city',
          parameters: {'type': 'object'},
        ),
      ];

      final handle = await provider.startRun(
        key: key,
        input: input0(tools: tools),
      );
      (await handle.events.toList())
          .whereType<DecodedEvent>()
          .map((d) => d.event)
          .toList();

      expect(capturedSystemPrompt, contains('You are helpful.'));
      expect(capturedSystemPrompt, contains('## Available Tools'));
      expect(capturedSystemPrompt, contains('### get_weather'));
      expect(capturedSystemPrompt, contains('tool_call'));
    });

    test('empty tools list omits tool instructions', () async {
      String? capturedSystemPrompt;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedSystemPrompt = systemPrompt;
          return 'ok';
        },
        systemPrompt: 'You are helpful.',
      );

      final handle = await provider.startRun(
        key: key,
        input: input0(tools: []),
      );
      (await handle.events.toList())
          .whereType<DecodedEvent>()
          .map((d) => d.event)
          .toList();

      expect(capturedSystemPrompt, contains('You are helpful.'));
      expect(capturedSystemPrompt, isNot(contains('## Available Tools')));
    });

    test('converts AG-UI messages to role/content pairs', () async {
      List<({String role, String? content})>? capturedMessages;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedMessages = messages;
          return 'ok';
        },
      );

      final input = input0(
        messages: [
          UserMessage(id: 'u1', content: 'Hello'),
          const AssistantMessage(id: 'a1', content: 'Hi there'),
          UserMessage(id: 'u2', content: 'Thanks'),
        ],
      );

      final handle = await provider.startRun(key: key, input: input);
      (await handle.events.toList())
          .whereType<DecodedEvent>()
          .map((d) => d.event)
          .toList();

      expect(capturedMessages, hasLength(3));
      expect(capturedMessages![0].role, 'user');
      expect(capturedMessages![0].content, 'Hello');
      expect(capturedMessages![1].role, 'assistant');
      expect(capturedMessages![1].content, 'Hi there');
      expect(capturedMessages![2].role, 'user');
      expect(capturedMessages![2].content, 'Thanks');
    });

    test('multimodal user content projects to a null content', () async {
      // The record carries text only, so a list-encoded content has no text
      // projection. Reporting `''` would claim the user sent an empty message
      // — itself a sendable value — so null is passed through instead and the
      // ChatFn decides what to do.
      List<({String role, String? content})>? capturedMessages;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedMessages = messages;
          return 'ok';
        },
      );

      final input = input0(
        messages: [
          UserMessage.multimodal(
            id: 'u1',
            parts: const [
              TextInputContent('what is this?'),
              ImageInputContent(
                source: UrlSource(value: 'https://example.com/cat.png'),
              ),
            ],
          ),
        ],
      );

      final handle = await provider.startRun(key: key, input: input);
      await handle.events.drain<void>();

      expect(capturedMessages, hasLength(1));
      expect(capturedMessages![0].role, 'user');
      expect(capturedMessages![0].content, isNull);
    });

    test('assistant with neither text nor tool calls projects to null',
        () async {
      // Not coalesced to `''`: that would pre-decide what the callback should
      // decide, and several chat APIs reject an empty assistant `content`.
      // Mirrors `LlmAssistantMessage.content`, which is nullable. Reachable in
      // production: `convertToAgui` emits an AssistantMessage carrying only
      // toolCalls, so an empty toolCalls list lands here.
      List<({String role, String? content})>? capturedMessages;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedMessages = messages;
          return 'ok';
        },
      );

      final input = input0(
        messages: [const AssistantMessage(id: 'a1')],
      );

      final handle = await provider.startRun(key: key, input: input);
      await handle.events.drain<void>();

      expect(capturedMessages, hasLength(1));
      expect(capturedMessages![0].role, 'assistant');
      expect(capturedMessages![0].content, isNull);
    });

    test('tool result messages formatted with prefix', () async {
      List<({String role, String? content})>? capturedMessages;
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async {
          capturedMessages = messages;
          return 'ok';
        },
      );

      final input = input0(
        messages: [
          const ToolMessage(
            id: 't1',
            content: '72°F, sunny',
            toolCallId: 'tc-1',
          ),
        ],
      );

      final handle = await provider.startRun(key: key, input: input);
      (await handle.events.toList())
          .whereType<DecodedEvent>()
          .map((d) => d.event)
          .toList();

      expect(capturedMessages, hasLength(1));
      expect(capturedMessages![0].role, 'user');
      expect(
        capturedMessages![0].content,
        "[Tool result for 'tc-1']: 72°F, sunny",
      );
    });

    test('cancelled token prevents event emission', () async {
      final cancelToken = CancelToken()..cancel('test');
      final provider = ChatFnLlmProvider(
        chatFn: (messages, {systemPrompt, maxTokens}) async => 'should not run',
      );

      final handle = await provider.startRun(
        key: key,
        input: input0(),
        cancelToken: cancelToken,
      );
      final events = await _decodedEvents(handle);

      // Only RunStartedEvent, then stream ends (cancelled before chatFn).
      expect(events[0], isA<RunStartedEvent>());
      expect(events, hasLength(1));
    });
  });
}

Future<List<BaseEvent>> _decodedEvents(LlmRunHandle handle) async =>
    (await handle.events.toList())
        .whereType<DecodedEvent>()
        .map((d) => d.event)
        .toList();
