import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_client/src/application/transcript_events.dart';
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
          ActivityMessage(
            :final id,
            :final activityType,
            :final activityContent
          ) =>
            'activity $id $activityType $activityContent',
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

    test('a reused id whose new call never ends takes no result', () {
      // call_0 ended with no result yet; a later call reuses the id and is
      // cut off. The earlier end must not vouch for the new call.
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p1'),
        ToolCallStartEvent(
          toolCallId: 'call_0',
          toolCallName: 'search',
          parentMessageId: 'p1',
        ),
        ToolCallEndEvent(toolCallId: 'call_0'),
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
        'assistant p2 ""',
      ]);
      expect(logs().single.attributes, {'toolCallId': 'call_0'});
      expect(logs().single.level, LogLevel.warning);
    });

    test('a call whose parent is not an assistant message takes no result', () {
      // The id a call names is already a user message's.
      final t = _apply(
        const [
          ToolCallStartEvent(
            toolCallId: 'c1',
            toolCallName: 'search',
            parentMessageId: 'u1',
          ),
          ToolCallEndEvent(toolCallId: 'c1'),
          ToolCallResultEvent(messageId: 'r1', toolCallId: 'c1', content: 'R'),
        ],
        const Transcript().withAppendedMessage(
          UserMessage(id: 'u1', content: 'Find it'),
        ),
      );

      expect(_describe(t), ['user u1']);
      expect(logs().map((r) => r.attributes['toolCallId']), ['c1', 'c1']);
    });

    group('a call that already has its result', () {
      final answered = _apply(const [
        TextMessageStartEvent(messageId: 'p'),
        ToolCallStartEvent(
          toolCallId: 'a',
          toolCallName: 'search',
          parentMessageId: 'p',
        ),
        ToolCallEndEvent(toolCallId: 'a'),
        ToolCallResultEvent(messageId: 'r1', toolCallId: 'a', content: 'RA'),
      ]);

      test('takes the same result again without a second copy', () {
        // A resumed run's input re-sends the results its events carried.
        final t = appendToolResult(
          answered,
          messageId: 'r1',
          toolCallId: 'a',
          content: 'RA',
        );

        expect(t, same(answered));
        expect(logs(), isEmpty);
      });
    });

    group('a call that names no parent', () {
      test('opens a new message for an id an earlier response used', () {
        // A provider numbering its calls per response gives each round's
        // call the same id; each round is its own response.
        const round = [
          ToolCallStartEvent(toolCallId: 'call_0', toolCallName: 'weather'),
          ToolCallEndEvent(toolCallId: 'call_0'),
        ];
        final first = appendToolResult(
          _apply(round),
          messageId: 'tool_result_call_0',
          toolCallId: 'call_0',
          content: 'Sunny',
        );

        final t = _apply(round, first);

        expect(_describe(t), [
          'assistant tool-calls-0 "" [call_0:weather({})]',
          'tool call_0 "Sunny"',
          'assistant tool-calls-2 "" [call_0:weather({})]',
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
          'assistant tool-calls-1 "" [tc-1:weather({}), tc-2:time({})]',
        ]);
      });
    });

    test('skips arguments and an end for a call that is not open', () {
      final t = _apply(const [
        TextMessageStartEvent(messageId: 'p'),
        ToolCallArgsEvent(toolCallId: 'c9', delta: '{}'),
        ToolCallEndEvent(toolCallId: 'c9'),
      ]);

      expect(_describe(t), ['assistant p ""']);
      expect(logs().map((r) => r.attributes), [
        {'toolCallId': 'c9'},
        {'toolCallId': 'c9'},
      ]);
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

    group('an activity', () {
      test('takes the place its first snapshot arrived at', () {
        const type = 'pydantic_ai_tool_availability_delta';
        final t = _apply(const [
          TextMessageStartEvent(messageId: 'm1'),
          ActivitySnapshotEvent(
            messageId: 'a1',
            activityType: type,
            content: {
              'added': ['search'],
            },
          ),
          TextMessageStartEvent(messageId: 'm2'),
          ActivitySnapshotEvent(
            messageId: 'a1',
            activityType: type,
            content: {
              'added': ['search', 'fetch'],
            },
          ),
        ]);

        expect(_describe(t), [
          'assistant m1 ""',
          'activity a1 $type {added: [search, fetch]}',
          'assistant m2 ""',
        ]);
      });

      test('keeps its content when a snapshot does not replace it', () {
        final t = _apply(const [
          ActivitySnapshotEvent(
            messageId: 'a1',
            activityType: 'progress',
            content: {'step': 1},
          ),
          ActivitySnapshotEvent(
            messageId: 'a1',
            activityType: 'progress',
            content: {'step': 2},
            replace: false,
          ),
        ]);

        expect(_describe(t), ['activity a1 progress {step: 1}']);
        expect(logs().single.attributes, {'messageId': 'a1'});
      });

      test('is patched by a delta', () {
        final t = _apply(const [
          ActivitySnapshotEvent(
            messageId: 'a1',
            activityType: 'progress',
            content: {'step': 1, 'total': 3},
          ),
          ActivityDeltaEvent(
            messageId: 'a1',
            activityType: 'progress',
            patch: [
              {'op': 'replace', 'path': '/step', 'value': 2},
            ],
          ),
        ]);

        expect(_describe(t), ['activity a1 progress {step: 2, total: 3}']);
      });

      test('a delta for a message that is not an activity is skipped', () {
        final t = _apply(const [
          TextMessageStartEvent(messageId: 'm1'),
          ActivityDeltaEvent(
            messageId: 'm1',
            activityType: 'progress',
            patch: [
              {'op': 'add', 'path': '/step', 'value': 1},
            ],
          ),
        ]);

        expect(_describe(t), ['assistant m1 ""']);
        expect(logs().single.attributes, {'messageId': 'm1'});
      });

      test('a delta with no snapshot before it creates the activity', () {
        final t = _apply(const [
          ActivityDeltaEvent(
            messageId: 'a1',
            activityType: 'progress',
            patch: [
              {'op': 'add', 'path': '/step', 'value': 1},
            ],
          ),
        ]);

        expect(_describe(t), ['activity a1 progress {step: 1}']);
      });
    });
  });
}
