import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('SkillToolCallActivity.fromRecord', () {
    test('decodes a well-formed skill_tool_call', () {
      const record = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hello","top_k":3}',
          'status': 'in_progress',
        },
        timestamp: 1234,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.messageId, 'rag:call_1');
      expect(call.toolName, 'ask');
      expect(call.status, SkillToolCallStatus.inProgress);
      expect(call.timestamp, 1234);
      expect(call.args, {'q': 'hello', 'top_k': 3});
    });

    test('missing args decodes to an empty map', () {
      const record = ActivityRecord(
        messageId: 'rag:call_2',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 10,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.args, isEmpty);
      expect(call.status, SkillToolCallStatus.inProgress);
    });

    test('empty args string decodes to an empty map', () {
      const record = ActivityRecord(
        messageId: 'rag:call_3',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': ''},
        timestamp: 11,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.args, isEmpty);
    });

    test('args already as a Map passes through', () {
      const record = ActivityRecord(
        messageId: 'rag:call_4',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': {'q': 'hi'},
        },
        timestamp: 12,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.args, {'q': 'hi'});
    });

    test('non-skill_tool_call activityType returns null', () {
      const record = ActivityRecord(
        messageId: 'plan:1',
        activityType: 'plan',
        content: {'steps': 3},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('missing tool_name returns null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_1',
        activityType: 'skill_tool_call',
        content: {'args': '{}'},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('non-string tool_name returns null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_2',
        activityType: 'skill_tool_call',
        content: {'tool_name': 42, 'args': '{}'},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('malformed args JSON returns null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_3',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': 'not json {'},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('args JSON that is not an object returns null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_4',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '[1,2,3]'},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('args with unexpected runtimeType returns null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_5',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': 42},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('non-string status falls back to synthesized inProgress', () {
      const record = ActivityRecord(
        messageId: 'rag:call_5',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '{}', 'status': 1},
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.status, SkillToolCallStatus.inProgress);
    });

    test('skill_tool_call without status synthesizes inProgress', () {
      const record = ActivityRecord(
        messageId: 'rag:call_no_status',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '{"q":"hi"}'},
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.status, SkillToolCallStatus.inProgress);
    });

    test('skill_tool_call with explicit status maps to enum', () {
      const record = ActivityRecord(
        messageId: 'rag:custom_status',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{}',
          'status': 'failed',
        },
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.status, SkillToolCallStatus.error);
    });

    test('decodes a well-formed skill_tool_result', () {
      const record = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'ask',
          'result': 'answer text',
        },
        timestamp: 1500,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.messageId, 'rag:call_1');
      expect(call.toolName, 'ask');
      expect(call.status, SkillToolCallStatus.done);
      expect(call.result, 'answer text');
      expect(call.args, isEmpty);
      expect(call.timestamp, 1500);
    });

    test('skill_tool_result with args in content decodes them', () {
      // Counterpart to the merge done in _applySnapshot: once args are
      // carried onto the result-phase record, the typed view must
      // surface them so the unified row keeps showing the inputs.
      const record = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hi","top_k":3}',
          'result': 'answer',
        },
        timestamp: 1500,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.args, {'q': 'hi', 'top_k': 3});
      expect(call.result, 'answer');
    });

    test('skill_tool_result with unrecognised status decodes as unknown', () {
      const record = ActivityRecord(
        messageId: 'rag:explicit_done',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'ask',
          'result': 'answer',
          'status': 'partial',
        },
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.status, SkillToolCallStatus.unknown);
      expect(call.result, 'answer');
    });

    test('skill_tool_result without result yields null result field', () {
      const record = ActivityRecord(
        messageId: 'rag:no_result',
        activityType: 'skill_tool_result',
        content: {'tool_name': 'ask'},
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.status, SkillToolCallStatus.done);
      expect(call.result, isNull);
    });

    test('skill_tool_result without tool_name returns null', () {
      // Regression guard: if a future backend ever omits tool_name from
      // the result snapshot, fromRecord must return null so the failure
      // is loud (row stays at spinner) rather than silently dropping
      // the completion.
      const record = ActivityRecord(
        messageId: 'rag:bad_result',
        activityType: 'skill_tool_result',
        content: {'result': 'orphan'},
        timestamp: 1,
      );

      expect(SkillToolCallActivity.fromRecord(record), isNull);
    });

    test('non-string result is coerced to null', () {
      const record = ActivityRecord(
        messageId: 'rag:bad_result_type',
        activityType: 'skill_tool_result',
        content: {'tool_name': 'ask', 'result': 42},
        timestamp: 1,
      );

      final call = SkillToolCallActivity.fromRecord(record);

      expect(call, isNotNull);
      expect(call!.result, isNull);
    });
  });

  group('SkillToolCallActivity equality', () {
    test('equal when fields match, including nested args', () {
      const a = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {
          'q': 'hi',
          'top_k': 3,
        },
        result: null,
        status: SkillToolCallStatus.done,
        timestamp: 1,
      );
      const b = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {
          'q': 'hi',
          'top_k': 3,
        },
        result: null,
        status: SkillToolCallStatus.done,
        timestamp: 1,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when args differ', () {
      const a = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {'q': 'hi'},
        result: null,
        status: SkillToolCallStatus.inProgress,
        timestamp: 1,
      );
      const b = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {'q': 'bye'},
        result: null,
        status: SkillToolCallStatus.inProgress,
        timestamp: 1,
      );

      expect(a, isNot(equals(b)));
    });

    test('not equal when result differs', () {
      const a = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {},
        result: 'first answer',
        status: SkillToolCallStatus.done,
        timestamp: 1,
      );
      const b = SkillToolCallActivity(
        messageId: 'm1',
        toolName: 'ask',
        args: {},
        result: 'second answer',
        status: SkillToolCallStatus.done,
        timestamp: 1,
      );

      expect(a, isNot(equals(b)));
    });

    test('toString includes identifying fields', () {
      const a = SkillToolCallActivity(
        messageId: 'rag:call_1',
        toolName: 'ask',
        args: {},
        result: null,
        status: SkillToolCallStatus.done,
        timestamp: 7,
      );
      final s = a.toString();
      expect(s, contains('rag:call_1'));
      expect(s, contains('ask'));
      expect(s, contains('done'));
      expect(s, contains('7'));
    });
  });
}
