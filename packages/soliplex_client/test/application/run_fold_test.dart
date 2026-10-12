import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/run_fold.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

class _RecordingSink implements LogSink {
  final List<LogRecord> records = [];

  @override
  void write(LogRecord record) {
    if (record.loggerName == 'soliplex_client.run_fold') records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

final _runStart = DateTime.utc(2026, 1, 7, 1);

/// The server time [seconds] into the run.
int _at(int seconds) =>
    _runStart.add(Duration(seconds: seconds)).millisecondsSinceEpoch;

/// A conversation holding the user's question, as both paths seed it before
/// the run's events: undated and with no run, as the live echo is.
Conversation _asked() => appendUserMessage(
      Conversation.empty(threadId: 't'),
      TextMessage.create(id: 'user-1', user: ChatUser.user, text: 'Q'),
    );

RunFold _start({
  Conversation? conversation,
  TurnCitations turnCitations = const TurnCitations.empty(),
}) =>
    RunFold.start(
      conversation ?? _asked(),
      runId: 'run-1',
      userMessageId: 'user-1',
      turnCitations: turnCitations,
      runCreated: _runStart,
    );

RunFold _applyAll(RunFold fold, List<BaseEvent> events) => events.fold(
      fold,
      (fold, event) => fold.apply(DecodedEvent(event, event.toJson())).fold,
    );

/// A reply the stream stopped partway through.
List<BaseEvent> _partialReply(int seconds) => [
      TextMessageStartEvent(messageId: 'msg-1', timestamp: _at(seconds)),
      TextMessageContentEvent(
        messageId: 'msg-1',
        delta: "I don'",
        timestamp: _at(seconds + 1),
      ),
    ];

/// A search the backend ran and answered within the run, so what the run
/// streamed holds more than it was sent.
List<BaseEvent> _serverSearch(int seconds) => [
      TextMessageStartEvent(messageId: 'p', timestamp: _at(seconds)),
      TextMessageEndEvent(messageId: 'p', timestamp: _at(seconds)),
      ToolCallStartEvent(
        toolCallId: 'call-search',
        toolCallName: 'search',
        parentMessageId: 'p',
        timestamp: _at(seconds + 1),
      ),
      ToolCallEndEvent(toolCallId: 'call-search', timestamp: _at(seconds + 1)),
      ToolCallResultEvent(
        messageId: 'r',
        toolCallId: 'call-search',
        content: 'evidence',
        timestamp: _at(seconds + 2),
      ),
    ];

StateSnapshotEvent _snapshot({
  required List<String> indexed,
  required List<String> cited,
}) =>
    StateSnapshotEvent(
      snapshot: {
        'rag': {
          'citation_index': {
            for (final id in indexed)
              id: {
                'chunk_id': id,
                'content': 'Text of $id',
                'document_id': 'doc-1',
                'document_uri': 'https://example.com/doc.pdf',
              },
          },
          'citations': cited,
        },
      },
    );

/// A state snapshot `processEvent` rejects: its snapshot is not an object.
const _unprocessableSnapshot =
    StateSnapshotEvent(snapshot: ['not', 'an', 'object']);

List<String?> _transcriptIds(Conversation conversation) =>
    [for (final message in conversation.transcript.messages) message.id];

void main() {
  group('RunFold.start', () {
    test('marks the run running', () {
      final fold = _start();

      expect(fold.conversation.status, const Running(runId: 'run-1'));
    });
  });

  group('RunFold.apply', () {
    test('folds a decoded event into the conversation and returns it', () {
      const event = TextMessageStartEvent(messageId: 'msg-1');

      final applied = _start().apply(DecodedEvent(event, event.toJson()));

      expect(applied.processed, same(event));
      expect(applied.fold.streaming, isA<TextStreaming>());
    });

    test('drops an event that could not be decoded in a tile of its own', () {
      final applied = _start().apply(
        const DecodeFailed(
          FormatException('not an event'),
          {'type': 'NOT_AN_EVENT'},
        ),
      );

      expect(applied.processed, isNull);
      expect(
        applied.fold.conversation.messages.last,
        isA<DroppedEventMessage>()
            .having((m) => m.id, 'id', 'dropped-run-1-0')
            .having((m) => m.source, 'source', DropSource.decode)
            .having((m) => m.runId, 'runId', 'run-1')
            .having((m) => m.rawPayload, 'rawPayload', {
          'type': 'NOT_AN_EVENT',
        }),
      );
    });

    test('drops an event processEvent rejects in a tile of its own', () {
      final applied = _start().apply(
        DecodedEvent(_unprocessableSnapshot, _unprocessableSnapshot.toJson()),
      );

      expect(applied.processed, isNull);
      expect(
        applied.fold.conversation.messages.last,
        isA<DroppedEventMessage>()
            .having((m) => m.source, 'source', DropSource.eventProcessing)
            .having(
              (m) => m.rawPayload,
              'rawPayload',
              _unprocessableSnapshot.toJson(),
            ),
      );
    });

    test("names a drop tile by the event's position in the run", () {
      // The backend stores one event per event it streams, so live and replay
      // give the tile the same id.
      final fold = _applyAll(_start(), _partialReply(1)).apply(
        const DecodeFailed(FormatException('not an event'), null),
      );

      expect(fold.fold.conversation.messages.last.id, 'dropped-run-1-2');
    });

    test('logs a drop without the payload its failure carries', () {
      final sink = _RecordingSink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      _start().apply(
        const DecodeFailed(
          FormatException('bad', '{"secret": "the user typed this"}'),
          null,
        ),
      );

      final record = sink.records.single;
      expect(record.error, isNull);
      expect(record.attributes['failure'], 'FormatException: bad');
    });

    test('dates a drop tile at the last event that carried a time', () {
      final applied = _applyAll(_start(), [
        RunStartedEvent(threadId: 't', runId: 'run-1', timestamp: _at(3)),
      ]).apply(const DecodeFailed(FormatException('not an event'), null));

      expect(
        applied.fold.conversation.messages.last.createdAt,
        DateTime.fromMillisecondsSinceEpoch(_at(3), isUtc: true),
      );
    });

    test('dates a drop tile at the run start before any event carried a time',
        () {
      final applied = _start().apply(
        const DecodeFailed(FormatException('not an event'), null),
      );

      expect(applied.fold.conversation.messages.last.createdAt, _runStart);
    });

    test('dates an event that carries no time at the last event before it', () {
      // The run's start would sort a failure row above the reply it follows.
      final fold = _applyAll(_start(), [
        ..._partialReply(1),
        const RunErrorEvent(message: 'boom'),
      ]);

      expect(
        fold.conversation.runOutcomes['run-1']!.createdAt,
        DateTime.fromMillisecondsSinceEpoch(_at(2), isUtc: true),
      );
    });

    test('ignores an event time outside the range a date can hold', () {
      final fold = _applyAll(_start(), [
        RunStartedEvent(
          threadId: 't',
          runId: 'run-1',
          timestamp: 8640000000000001,
        ),
        const RunErrorEvent(message: 'boom'),
      ]);

      expect(fold.conversation.runOutcomes['run-1']!.createdAt, _runStart);
    });

    test("stamps the turn's user message with the run and its start", () {
      final fold = _applyAll(_start(), [
        RunStartedEvent(threadId: 't', runId: 'run-1', timestamp: _at(5)),
      ]);

      final user = fold.conversation.messages.single;
      expect(user.runId, 'run-1');
      expect(
        user.createdAt,
        DateTime.fromMillisecondsSinceEpoch(_at(5), isUtc: true),
      );
    });

    test('leaves a user message that already has a run and a time as it is',
        () {
      // A client tool's continuation run carries the turn's user message too;
      // the message stays with the run that sent it.
      final sentAt = DateTime.utc(2026);
      final asked = appendUserMessage(
        Conversation.empty(threadId: 't'),
        TextMessage.create(
          id: 'user-1',
          user: ChatUser.user,
          text: 'Q',
          runId: 'run-0',
          createdAt: sentAt,
        ),
      );

      final fold = _applyAll(_start(conversation: asked), [
        RunStartedEvent(threadId: 't', runId: 'run-1', timestamp: _at(0)),
      ]);

      final user = fold.conversation.messages.single;
      expect(user.runId, 'run-0');
      expect(user.createdAt, sentAt);
    });
  });

  group('RunFold.resolveTurn', () {
    test("records the turn's sources against this run", () {
      final fold = _applyAll(_start(), [
        _snapshot(indexed: ['chunk-1'], cited: ['chunk-1']),
      ]).resolveTurn();

      final state = fold.conversation.messageStates['user-1']!;
      expect(state.runId, 'run-1');
      expect(state.sourceReferences.map((s) => s.chunkId), ['chunk-1']);
    });

    test('keeps what earlier runs of the turn cited', () {
      final earlier = _applyAll(_start(), [
        _snapshot(indexed: ['chunk-1'], cited: ['chunk-1']),
      ]);

      final fold = _applyAll(
        _start(
          conversation: earlier.conversation,
          turnCitations: earlier.turnCitations,
        ),
        [
          _snapshot(indexed: ['chunk-1', 'chunk-2'], cited: ['chunk-2']),
        ],
      ).resolveTurn();

      expect(
        fold.conversation.messageStates['user-1']!.sourceReferences
            .map((s) => s.chunkId),
        ['chunk-1', 'chunk-2'],
      );
    });

    test('records nothing for a run with no user message', () {
      final fold = RunFold.start(
        Conversation.empty(threadId: 't'),
        runId: 'run-1',
        userMessageId: null,
        turnCitations: const TurnCitations.empty(),
      ).resolveTurn();

      expect(fold.conversation.messageStates, isEmpty);
    });
  });

  group('RunFold.failed', () {
    test('parks a failed outcome with the detail', () {
      final fold = _start().failed('lost it', terminalEvent: 'test');

      expect(
        fold.conversation.runOutcomes['run-1'],
        isA<NoResponseTile>()
            .having((t) => t.reason, 'reason', TerminalReason.failed)
            .having((t) => t.errorDetail, 'errorDetail', 'lost it'),
      );
    });

    test('dates the outcome and the reply at the last event', () {
      final fold = _applyAll(_start(), _partialReply(1))
          .failed('lost it', terminalEvent: 'test');

      final lastEvent =
          DateTime.fromMillisecondsSinceEpoch(_at(2), isUtc: true);
      expect(fold.conversation.messages.last.createdAt, lastEvent);
      expect(fold.conversation.runOutcomes['run-1']!.createdAt, lastEvent);
    });

    test('commits the reply the run was streaming', () {
      final fold = _applyAll(_start(), _partialReply(1))
          .failed('lost it', terminalEvent: 'test');

      expect(
        fold.conversation.messages.last,
        isA<TextMessage>()
            .having((m) => m.id, 'id', 'msg-1')
            .having((m) => m.text, 'text', "I don'")
            .having((m) => m.runId, 'runId', 'run-1'),
      );
      expect(fold.streaming, isA<AwaitingText>());
    });

    test('keeps what the run was sent when no state snapshot was processed',
        () {
      final sent = _transcriptIds(_asked());

      final fold = _applyAll(_start(), [
        ..._serverSearch(1),
        _unprocessableSnapshot,
      ]).failed('lost it', terminalEvent: 'test');

      expect(_transcriptIds(fold.conversation), sent);
    });

    test('keeps what the run streamed once its state snapshot was processed',
        () {
      final fold = _applyAll(_start(), [
        ..._serverSearch(1),
        _snapshot(indexed: const [], cited: const []),
      ]).failed('lost it', terminalEvent: 'test');

      expect(_transcriptIds(fold.conversation), ['user-1', 'p', 'r']);
    });

    test('keeps what the run streamed once its terminal event was processed',
        () {
      // An ending recorded after the run completed, such as a client tool
      // failing while the run waits on it.
      final fold = _applyAll(_start(), [
        ..._serverSearch(1),
        const RunFinishedEvent(threadId: 't', runId: 'run-1'),
      ]).failed('lost it', terminalEvent: 'test');

      expect(_transcriptIds(fold.conversation), ['user-1', 'p', 'r']);
    });
  });

  group('RunFold.cutOffDetail', () {
    test('says the stream ended when every event was read', () {
      final fold = _applyAll(_start(), _partialReply(1));

      expect(fold.cutOffDetail, 'Stream ended without terminal event');
    });

    test('says events went unread when one became a drop tile', () {
      final fold = _start().apply(
        DecodedEvent(_unprocessableSnapshot, _unprocessableSnapshot.toJson()),
      );

      expect(
        fold.fold.cutOffDetail,
        "Some of this run's events could not be read",
      );
    });
  });

  group('RunFold.cancelled', () {
    test('parks a cancelled outcome', () {
      final fold = _start().cancelled(terminalEvent: 'test');

      expect(
        fold.conversation.runOutcomes['run-1']!.reason,
        TerminalReason.cancelled,
      );
    });

    test('commits the reply the run was streaming', () {
      final fold = _applyAll(_start(), _partialReply(1))
          .cancelled(terminalEvent: 'test');

      expect(
        fold.conversation.messages.last,
        isA<TextMessage>().having((m) => m.text, 'text', "I don'"),
      );
      expect(fold.streaming, isA<AwaitingText>());
    });

    test('keeps what the run was sent when no state snapshot was processed',
        () {
      final fold = _applyAll(_start(), _serverSearch(1))
          .cancelled(terminalEvent: 'test');

      expect(_transcriptIds(fold.conversation), _transcriptIds(_asked()));
    });
  });
}
