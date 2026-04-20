import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityRecord', () {
    test('fields are preserved on construction', () {
      const record = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '{"q":"hi"}'},
        timestamp: 1234,
      );
      expect(record.messageId, 'rag:call_1');
      expect(record.activityType, 'skill_tool_call');
      expect(record.content['tool_name'], 'ask');
      expect(record.timestamp, 1234);
    });

    test('equality based on all fields', () {
      const a = ActivityRecord(
        messageId: 'm1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 1,
      );
      const b = ActivityRecord(
        messageId: 'm1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 1,
      );
      const c = ActivityRecord(
        messageId: 'm1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'search'},
        timestamp: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only the given fields', () {
      const a = ActivityRecord(
        messageId: 'm1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask'},
        timestamp: 1,
      );
      final b = a.copyWith(timestamp: 2);
      expect(b.messageId, a.messageId);
      expect(b.activityType, a.activityType);
      expect(b.content, a.content);
      expect(b.timestamp, 2);
    });

    test('toString includes identifying fields', () {
      const a = ActivityRecord(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {},
        timestamp: 7,
      );
      final s = a.toString();
      expect(s, contains('rag:call_1'));
      expect(s, contains('skill_tool_call'));
      expect(s, contains('7'));
    });
  });
}
