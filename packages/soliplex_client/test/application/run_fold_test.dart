import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/run_fold.dart';
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

/// A conversation holding the user's question, as live seeds it before the
/// run's events: undated and with no run.
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

/// A state snapshot `processEvent` rejects: its snapshot is not an object.
const _unprocessableSnapshot =
    StateSnapshotEvent(snapshot: ['not', 'an', 'object']);

List<String?> _transcriptIds(Conversation conversation) =>
    [for (final message in conversation.transcript.messages) message.id];

void main() {
  group('RunFold.apply', () {
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
  });

  group('RunFold.resolveTurn', () {
    test('records nothing for a run with no user message', () {
      final fold = RunFold.start(
        Conversation.empty(threadId: 't'),
        runId: 'run-1',
        userMessageId: null,
        turnCitations: const TurnCitations.empty(),
        runCreated: null,
      ).resolveTurn();

      expect(fold.conversation.messageStates, isEmpty);
    });
  });

  group('RunFold.failed', () {
    test('dates the outcome and the reply at the last event', () {
      final fold = _applyAll(_start(), _partialReply(1))
          .failed('lost it', terminalEvent: 'test');

      final lastEvent =
          DateTime.fromMillisecondsSinceEpoch(_at(2), isUtc: true);
      expect(fold.conversation.messages.last.createdAt, lastEvent);
      expect(fold.conversation.runOutcomes['run-1']!.createdAt, lastEvent);
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
}
