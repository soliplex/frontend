import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

Transcript _apply(
  List<BaseEvent> events, [
  Transcript from = const Transcript(),
]) =>
    events.fold(from, applyTranscriptEvent);

/// One line per message, naming what the wire carries.
List<String> _describe(Transcript transcript) => [
      for (final m in transcript.messages)
        switch (m) {
          AssistantMessage(:final id, :final content, :final toolCalls) => [
              'assistant $id "${content ?? ''}"',
              if (toolCalls != null)
                '[${toolCalls.map(
                      (c) => '${c.id}:${c.function.name}'
                          '(${c.function.arguments})',
                    ).join(', ')}]',
            ].join(' '),
          ToolMessage(:final toolCallId, :final content) =>
            'tool $toolCallId "$content"',
          UserMessage(:final id) => 'user $id',
          _ => m.runtimeType.toString(),
        },
    ];

void main() {
  late MemorySink sink;
  setUp(() {
    sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
  });
  List<LogRecord> logs() => sink.records
      .where((r) => r.loggerName == 'soliplex_client.transcript')
      .toList();

  group('applyTranscriptEvent', () {
    test('keeps a response with text and a call in event order', () {
      // pydantic-ai: text, then a call parented on it, then a new text
      // message for text after the call, then the result once the call ran.
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'm1'),
        TextMessageContentEvent(messageId: 'm1', delta: 'Look'),
        TextMessageContentEvent(messageId: 'm1', delta: 'ing'),
        TextMessageEndEvent(messageId: 'm1'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'm1',
        ),
        ToolCallArgsEvent(toolCallId: 'call_0', delta: '{"q":'),
        ToolCallArgsEvent(toolCallId: 'call_0', delta: '"x"}'),
        ToolCallEndEvent(toolCallId: 'call_0'),
        TextMessageStartEvent(messageId: 'm2'),
        TextMessageContentEvent(messageId: 'm2', delta: 'Done'),
        TextMessageEndEvent(messageId: 'm2'),
        ToolCallResultEvent(
          messageId: 'r1',
          toolCallId: 'call_0',
          content: 'R',
        ),
      ]);

      expect(_describe(t), [
        'assistant m1 "Looking" [call_0:search({"q":"x"})]',
        'assistant m2 "Done"',
        'tool call_0 "R"',
      ]);
      expect(logs(), isEmpty);
    });

    test('carries a tool-only response on the empty message opened for it', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p'),
        TextMessageEndEvent(messageId: 'p'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p',
        ),
        ToolCallArgsEvent(toolCallId: 'call_0', delta: '{}'),
        ToolCallEndEvent(toolCallId: 'call_0'),
      ]);

      expect(_describe(t), ['assistant p "" [call_0:search({})]']);
    });

    test('creates the parent a call names when nothing opened it', () {
      // Older pydantic-ai opened no message before a tool-only response.
      final t = _apply(const [
        ToolCallStartEvent(
          toolCallId: 'c1',
          toolCallName: 'search',
          parentMessageId: 'unopened',
        ),
        ToolCallEndEvent(toolCallId: 'c1'),
      ]);

      expect(_describe(t), ['assistant unopened "" [c1:search({})]']);
    });

    test('sends an ended call with no arguments as an empty object', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p'),
        ToolCallStartEvent(
          toolCallId: 'c1',
          toolCallName: 'now',
          parentMessageId: 'p',
        ),
        ToolCallEndEvent(toolCallId: 'c1'),
      ]);

      expect(
        (t.messages.single as AssistantMessage)
            .toolCalls!
            .single
            .function
            .arguments,
        '{}',
      );
    });

    test('does not send a call that never ended, nor a result for it', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p'),
        ToolCallStartEvent(
          toolCallId: 'c1',
          toolCallName: 'search',
          parentMessageId: 'p',
        ),
        ToolCallArgsEvent(toolCallId: 'c1', delta: '{"q":"x'),
        ToolCallResultEvent(messageId: 'r1', toolCallId: 'c1', content: 'R'),
      ]);

      expect(_describe(t), ['assistant p ""']);
      expect(logs().single.attributes, {'toolCallId': 'c1'});
      expect(logs().single.level, LogLevel.warning);
    });

    test('a start for an id still open replaces it', () {
      // A stopped run left call_0 open; the next run's server numbers its
      // first call call_0 again.
      final stopped = _apply(const [
        TextMessageStartEvent(messageId: 'p1'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p1',
        ),
        ToolCallArgsEvent(toolCallId: 'call_0', delta: '{"q":"x'),
      ]);
      final t = _apply(
        const [
          TextMessageStartEvent(messageId: 'p2'),
          ToolCallStartEvent(
            toolCallId: 'call_0',
            toolCallName: 'fetch',
            parentMessageId: 'p2',
          ),
          ToolCallArgsEvent(toolCallId: 'call_0', delta: '{}'),
          ToolCallEndEvent(toolCallId: 'call_0'),
        ],
        stopped,
      );

      expect(_describe(t), [
        'assistant p1 ""',
        'assistant p2 "" [call_0:fetch({})]',
      ]);
      expect(logs().single.attributes, {'toolCallId': 'call_0'});
    });

    test('an id reused after its call ended starts a new call', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p1'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p1',
        ),
        ToolCallEndEvent(toolCallId: 'call_0'),
        ToolCallResultEvent(
          messageId: 'r1',
          toolCallId: 'call_0',
          content: 'A',
        ),
        TextMessageStartEvent(messageId: 'p2'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p2',
        ),
        ToolCallEndEvent(toolCallId: 'call_0'),
        ToolCallResultEvent(
          messageId: 'r2',
          toolCallId: 'call_0',
          content: 'B',
        ),
      ]);

      expect(_describe(t), [
        'assistant p1 "" [call_0:search({})]',
        'tool call_0 "A"',
        'assistant p2 "" [call_0:search({})]',
        'tool call_0 "B"',
      ]);
      expect(logs(), isEmpty);
    });

    test('a reused id whose new call never ends takes no result', () {
      // call_0 ended and was answered; a later call reuses the id and is cut
      // off. The earlier end must not vouch for the new call.
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p1'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p1',
        ),
        ToolCallEndEvent(toolCallId: 'call_0'),
        ToolCallResultEvent(
          messageId: 'r1',
          toolCallId: 'call_0',
          content: 'A',
        ),
        TextMessageStartEvent(messageId: 'p2'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p2',
        ),
        ToolCallResultEvent(
          messageId: 'r2',
          toolCallId: 'call_0',
          content: 'B',
        ),
      ]);

      expect(_describe(t), [
        'assistant p1 "" [call_0:search({})]',
        'tool call_0 "A"',
        'assistant p2 ""',
      ]);
      expect(logs().single.attributes, {'toolCallId': 'call_0'});
    });

    group('a call that names no parent', () {
      test('joins the assistant message it follows', () {
        // StreamingLlmProvider: one response's text, then its calls.
        final t = _apply(const [
          TextMessageStartEvent(messageId: 'msg-1'),
          TextMessageContentEvent(messageId: 'msg-1', delta: 'Checking'),
          TextMessageEndEvent(messageId: 'msg-1'),
          ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
          ToolCallEndEvent(toolCallId: 'tc-1'),
          ToolCallStartEvent(toolCallId: 'tc-2', toolCallName: 'time'),
          ToolCallEndEvent(toolCallId: 'tc-2'),
        ]);

        expect(_describe(t), [
          'assistant msg-1 "Checking" [tc-1:weather({}), tc-2:time({})]',
        ]);
      });

      test('opens an assistant message when the last message is not one', () {
        final t = _apply(
          const [
            ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather'),
            ToolCallEndEvent(toolCallId: 'tc-1'),
            ToolCallStartEvent(toolCallId: 'tc-2', toolCallName: 'time'),
            ToolCallEndEvent(toolCallId: 'tc-2'),
          ],
          const Transcript().withAppendedMessage(
            UserMessage(id: 'u1', content: 'Weather?'),
          ),
        );

        expect(_describe(t), [
          'user u1',
          'assistant tool-calls-tc-1 "" [tc-1:weather({}), tc-2:time({})]',
        ]);
      });
    });

    test('skips a text start for an id it already holds', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'm1'),
        TextMessageContentEvent(messageId: 'm1', delta: 'Hi'),
        TextMessageStartEvent(messageId: 'm1'),
      ]);

      expect(_describe(t), ['assistant m1 "Hi"']);
      expect(logs().single.attributes, {'messageId': 'm1'});
    });

    test('skips content for a message it does not hold', () {
      final t = _apply(const [
        TextMessageContentEvent(messageId: 'm9', delta: 'Hi'),
      ]);

      expect(t.messages, isEmpty);
      expect(logs().single.attributes, {'messageId': 'm9'});
    });

    test('ignores a messages snapshot', () {
      final before = _apply(const [TextMessageStartEvent(messageId: 'm1')]);

      final after = applyTranscriptEvent(
        before,
        MessagesSnapshotEvent(messages: const []),
      );

      expect(after, same(before));
    });

    group('an encrypted value', () {
      const claim = '{"pydantic_ai":{"tool_kind":"capability-load"}}';

      test('goes out with the open call it names', () {
        final t = _apply(const [
          TextMessageStartEvent(messageId: 'p'),
          ToolCallStartEvent(
            toolCallId: 'c1',
            toolCallName: 'load_capability',
            parentMessageId: 'p',
          ),
          ReasoningEncryptedValueEvent(
            subtype: ReasoningEncryptedValueSubtype.toolCall,
            entityId: 'c1',
            encryptedValue: claim,
          ),
          ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
          ToolCallEndEvent(toolCallId: 'c1'),
        ]);

        final call = (t.messages.single as AssistantMessage).toolCalls!.single;
        expect(call.encryptedValue, claim);
        expect(call.toJson()['encryptedValue'], claim);
        expect(logs(), isEmpty);
      });

      test('for a call that is not open is dropped', () {
        final t = _apply(const [
          ReasoningEncryptedValueEvent(
            subtype: ReasoningEncryptedValueSubtype.toolCall,
            entityId: 'c9',
            encryptedValue: claim,
          ),
        ]);

        expect(t.messages, isEmpty);
        expect(logs().single.attributes, {'toolCallId': 'c9'});
      });

      test('for a message is dropped', () {
        final before = _apply(const [TextMessageStartEvent(messageId: 'm1')]);

        final after = applyTranscriptEvent(
          before,
          const ReasoningEncryptedValueEvent(
            subtype: ReasoningEncryptedValueSubtype.message,
            entityId: 'm1',
            encryptedValue: 'opaque',
          ),
        );

        expect(after, same(before));
        expect(logs().single.attributes, {'entityId': 'm1'});
      });
    });
  });
}
