import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

class _RecordingSink implements LogSink {
  _RecordingSink({required this.forLoggerName});

  /// Only records from this logger are captured; everything else the
  /// singleton sees during the test is ignored. Keeps assertions strict
  /// without coupling to the rest of the codebase's log traffic.
  final String forLoggerName;
  final List<LogRecord> records = [];

  @override
  void write(LogRecord record) {
    if (record.loggerName == forLoggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

void main() {
  final logger = LogManager.instance.getLogger('test.activity_events');

  group('applyActivityEvent — snapshot', () {
    test('appends a new record when no prior entry exists', () {
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '{"q":"hi"}'},
        timestamp: 100,
      );

      final result = applyActivityEvent(const [], event, logger: logger);

      expect(result, hasLength(1));
      expect(result.single.messageId, 'rag:call_1');
      expect(result.single.timestamp, 100);
    });

    test('replaces in place when replace=true', () {
      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 100,
      );
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {'tool_name': 'ask', 'result': 'answer'},
        timestamp: 200,
      );

      final result = applyActivityEvent([initial], event, logger: logger);

      expect(result, hasLength(1));
      expect(result.single.activityType, 'skill_tool_result');
      expect(result.single.content['result'], 'answer');
      expect(result.single.timestamp, 200);
    });

    test('skill_tool_result snapshot merges args from prior call record', () {
      // Unified-row UI contract: AG-UI replaces the call snapshot with a
      // result snapshot at the same messageId. The result phase does not
      // carry args, so storage drops them unless the application layer
      // bridges across the replace boundary.
      const call = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hi"}',
        },
        timestamp: 100,
      );
      const result = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'ask',
          'result': 'answer',
        },
        timestamp: 200,
      );

      final after = applyActivityEvent([call], result, logger: logger);

      expect(after, hasLength(1));
      expect(after.single.activityType, 'skill_tool_result');
      expect(after.single.content['result'], 'answer');
      expect(after.single.content['args'], '{"q":"hi"}');
    });

    test(
        'skill_tool_result snapshot does not overwrite args carried by '
        'the event', () {
      // Defensive: if a future backend ships args on the result phase,
      // its value wins over the call-phase carry-over.
      const call = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"old"}',
        },
        timestamp: 100,
      );
      const result = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"new"}',
          'result': 'answer',
        },
        timestamp: 200,
      );

      final after = applyActivityEvent([call], result, logger: logger);

      expect(after.single.content['args'], '{"q":"new"}');
    });

    test('preserves prior record when replace=false and id collides', () {
      // Live and historical paths must agree on AG-UI's replace=false
      // semantic: a duplicate-id snapshot without replace is ignored.
      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'first', 'args': '{"q":"first"}'},
        timestamp: 100,
      );
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'second', 'args': '{"q":"second"}'},
        replace: false,
        timestamp: 200,
      );

      final result = applyActivityEvent([initial], event, logger: logger);

      expect(result, hasLength(1));
      expect(result.single.content['tool_name'], 'first');
      expect(result.single.timestamp, 100);
    });

    test('skips a snapshot whose content is not a JSON object', () {
      // AG-UI types `content` as `Object?`, so the protocol permits any
      // JSON shape. `ActivityRecord.content` is a map, so a non-object
      // payload is dropped with a warning rather than crashing the stream.
      final sink = _RecordingSink(forLoggerName: 'test.activity_events');
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 100,
      );
      const event = ActivitySnapshotEvent(
        messageId: 'rag:call_2',
        activityType: 'skill_tool_call',
        content: 'not-a-map',
        timestamp: 200,
      );

      final current = [initial];
      final result = applyActivityEvent(current, event, logger: logger);

      // Identity, not just equality: callers short-circuit on
      // `identical(updatedActivities, conversation.activities)` to avoid
      // minting a new Conversation, so returning a fresh copy would cause
      // silent rebuild churn downstream. This input reaches the fold only from
      // historical replay — `_processActivitySnapshot` throws on a non-object
      // `content` before folding.
      expect(result, same(current));
      expect(sink.records, hasLength(1));
      final record = sink.records.single;
      expect(record.level, LogLevel.warning);
      expect(record.attributes['messageId'], 'rag:call_2');
      expect(record.attributes['contentType'], 'String');
    });
  });

  group('applyActivityEvent — delta', () {
    test('applies JSON Patch to the matching record', () {
      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'status': 'in_progress'},
        timestamp: 100,
      );
      const event = ActivityDeltaEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
        ],
        timestamp: 200,
      );

      final result = applyActivityEvent([initial], event, logger: logger);

      expect(result.single.content['status'], 'done');
      expect(result.single.timestamp, 200);
    });

    test('drops when no prior snapshot exists', () {
      const event = ActivityDeltaEvent(
        messageId: 'rag:orphan',
        activityType: 'skill_tool_call',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
        ],
      );

      final result = applyActivityEvent(const [], event, logger: logger);

      expect(result, isEmpty);
    });

    test('drops when activityType disagrees with prior record', () {
      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'status': 'in_progress'},
        timestamp: 100,
      );
      const event = ActivityDeltaEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
        ],
        timestamp: 200,
      );

      final result = applyActivityEvent([initial], event, logger: logger);

      // Existing record is preserved unchanged.
      expect(result.single.activityType, 'skill_tool_call');
      expect(result.single.content['status'], 'in_progress');
      expect(result.single.timestamp, 100);
    });

    test('logs error with structured attrs when no prior snapshot exists', () {
      // Backend escalation contract: every delta-drop branch must log
      // exactly one record, at error level, with messageId / activityType
      // / patchOps attributes so backend triage can reconstruct the
      // dropped patch. Sink filtering keeps the assertion strict against
      // noise additions on the same path.
      final sink = _RecordingSink(forLoggerName: 'test.activity_events');
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      const event = ActivityDeltaEvent(
        messageId: 'rag:orphan',
        activityType: 'skill_tool_call',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
          {'op': 'add', 'path': '/progress', 'value': 0.5},
        ],
      );

      applyActivityEvent(const [], event, logger: logger);

      expect(sink.records, hasLength(1));
      final record = sink.records.single;
      expect(record.level, LogLevel.error);
      expect(record.attributes['messageId'], 'rag:orphan');
      expect(record.attributes['activityType'], 'skill_tool_call');
      expect(record.attributes['patchOps'], 2);
    });

    test('logs error with structured attrs when activityType disagrees', () {
      final sink = _RecordingSink(forLoggerName: 'test.activity_events');
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'status': 'in_progress'},
        timestamp: 100,
      );
      const event = ActivityDeltaEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        patch: [
          {'op': 'replace', 'path': '/status', 'value': 'done'},
        ],
        timestamp: 200,
      );

      applyActivityEvent([initial], event, logger: logger);

      expect(sink.records, hasLength(1));
      final record = sink.records.single;
      expect(record.level, LogLevel.error);
      expect(record.attributes['messageId'], 'rag:call_1');
      expect(record.attributes['expected'], 'skill_tool_call');
      expect(record.attributes['received'], 'skill_tool_result');
      expect(record.attributes['patchOps'], 1);
    });

    test('inherits prior timestamp when event omits one', () {
      const initial = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'status': 'in_progress'},
        timestamp: 500,
      );
      const event = ActivityDeltaEvent(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        patch: [
          {'op': 'add', 'path': '/progress', 'value': 0.5},
        ],
      );

      final result = applyActivityEvent([initial], event, logger: logger);

      expect(result.single.timestamp, 500);
    });
  });

  test('returns the input list unchanged for non-activity events', () {
    const initial = ActivityRecord(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask'},
      timestamp: 100,
    );

    final result = applyActivityEvent(
      [initial],
      const TextMessageStartEvent(messageId: 'asst-1'),
      logger: logger,
    );

    expect(identical(result, [initial]) || result.length == 1, isTrue);
    expect(result.single.messageId, 'rag:call_1');
  });
}
