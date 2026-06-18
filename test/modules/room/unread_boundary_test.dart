import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/compute_display_messages.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

TextMessage _msg(String id) =>
    TextMessage.create(id: id, user: ChatUser.assistant, text: id);

void main() {
  group('firstUnreadMessageId', () {
    final messages = [_msg('a'), _msg('b'), _msg('c')];

    test('returns the message after the anchor', () {
      expect(firstUnreadMessageId(messages, 'a'), 'b');
      expect(firstUnreadMessageId(messages, 'b'), 'c');
    });

    test('null when no anchor', () {
      expect(firstUnreadMessageId(messages, null), isNull);
    });

    test('null when anchor is the last message', () {
      expect(firstUnreadMessageId(messages, 'c'), isNull);
    });

    test('null when anchor is absent from the list', () {
      expect(firstUnreadMessageId(messages, 'zzz'), isNull);
    });

    test('null for an empty list', () {
      expect(firstUnreadMessageId(const [], 'a'), isNull);
    });

    test('null when the next message is the loading sentinel', () {
      final messages = [_msg('a'), LoadingMessage.create(id: loadingMessageId)];
      expect(firstUnreadMessageId(messages, 'a'), isNull);
    });
  });

  group('lastRealMessageId', () {
    test('returns the last id', () {
      expect(lastRealMessageId([_msg('a'), _msg('b')]), 'b');
    });

    test('skips the loading sentinel', () {
      final messages = [_msg('a'), LoadingMessage.create(id: loadingMessageId)];
      expect(lastRealMessageId(messages), 'a');
    });

    test('null when empty or only ephemeral', () {
      expect(lastRealMessageId(const []), isNull);
      expect(
        lastRealMessageId([LoadingMessage.create(id: loadingMessageId)]),
        isNull,
      );
    });
  });
}
