import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('TextMessage', () {
    test('create with required fields', () {
      final message = TextMessage.create(
        id: 'msg-1',
        user: ChatUser.user,
        text: 'Hello',
      );

      expect(message.user, equals(ChatUser.user));
      expect(message.text, equals('Hello'));
      expect(message.isStreaming, isFalse);
      expect(message.id, equals('msg-1'));
      // createdAt is omitted, so it defaults to null — the model never
      // substitutes a client-generated time.
      expect(message.createdAt, isNull);
    });

    test('create with all fields', () {
      final message = TextMessage.create(
        user: ChatUser.assistant,
        text: 'Response',
        id: 'custom-id',
        isStreaming: true,
      );

      expect(message.id, equals('custom-id'));
      expect(message.user, equals(ChatUser.assistant));
      expect(message.text, equals('Response'));
      expect(message.isStreaming, isTrue);
    });

    test('equality by id', () {
      final msg1 = TextMessage.create(
        id: 'same-id',
        user: ChatUser.user,
        text: 'Hello',
      );
      final msg2 = TextMessage.create(
        id: 'same-id',
        user: ChatUser.assistant,
        text: 'Different',
      );

      expect(msg1, equals(msg2));
    });

    test('not equal with different id', () {
      final msg1 = TextMessage.create(
        id: 'id1',
        user: ChatUser.user,
        text: 'Hello',
      );
      final msg2 = TextMessage.create(
        id: 'id2',
        user: ChatUser.user,
        text: 'Hello',
      );

      expect(msg1, isNot(equals(msg2)));
    });

    test('hasThinkingText returns true when thinking text is present', () {
      final message = TextMessage(
        id: 'test-id',
        user: ChatUser.assistant,
        createdAt: DateTime.now(),
        text: 'Response',
        thinkingText: 'I am thinking...',
      );

      expect(message.hasThinkingText, isTrue);
    });

    test('hasThinkingText returns false when thinking text is empty', () {
      final message = TextMessage.create(
        id: 'msg-1',
        user: ChatUser.assistant,
        text: 'Response',
      );

      expect(message.hasThinkingText, isFalse);
    });
  });

  group('NoResponseTile', () {
    test('synthesized tile is always an assistant message', () {
      final tile = NoResponseTile.finished(
        id: 'no-response-run-1',
        thinkingText: '',
      );

      expect(tile.user, equals(ChatUser.assistant));
    });

    test('hasThinkingText reflects thinking content', () {
      final empty = NoResponseTile.failed(
        id: 'no-response-run-1',
        thinkingText: '',
        errorDetail: 'boom',
      );
      final filled = NoResponseTile.failed(
        id: 'no-response-run-2',
        thinkingText: 'reasoning',
        errorDetail: 'boom',
      );

      expect(empty.hasThinkingText, isFalse);
      expect(filled.hasThinkingText, isTrue);
    });

    test('failed factory carries errorDetail; cancelled factory has none', () {
      final failed = NoResponseTile.failed(
        id: 'no-response-run-1',
        thinkingText: '',
        errorDetail: 'rate limit',
      );
      final cancelled = NoResponseTile.cancelled(
        id: 'no-response-run-2',
        thinkingText: '',
      );

      expect(failed.reason, equals(TerminalReason.failed));
      expect(failed.errorDetail, equals('rate limit'));
      expect(cancelled.reason, equals(TerminalReason.cancelled));
      expect(cancelled.errorDetail, isNull);
    });
  });

  group('DroppedEventMessage', () {
    test('user is system (not assistant or user)', () {
      // The constructor hardcodes ChatUser.system. Encoded decision:
      // dropped events are diagnostics, not chat turns from any party.
      final message = DroppedEventMessage.create(
        id: 'drop-1',
        source: DropSource.decode,
        reason: 'unknown event type',
      );

      expect(message.user, equals(ChatUser.system));
    });
  });

  group('ErrorMessage', () {
    test('create with message', () {
      final message = ErrorMessage.create(
        id: 'error-1',
        message: 'Something went wrong',
      );

      expect(message.user, equals(ChatUser.system));
      expect(message.errorText, equals('Something went wrong'));
      expect(message.id, equals('error-1'));
    });

    test('create with custom id', () {
      final message = ErrorMessage.create(id: 'error-id', message: 'Error');

      expect(message.id, equals('error-id'));
    });

    test('equality by id', () {
      final msg1 = ErrorMessage.create(id: 'same-id', message: 'Error 1');
      final msg2 = ErrorMessage.create(id: 'same-id', message: 'Error 2');

      expect(msg1, equals(msg2));
    });
  });

  group('ToolCallMessage', () {
    test('create with tool calls', () {
      final message = ToolCallMessage.create(
        id: 'tc-msg-1',
        toolCalls: const [ToolCallInfo(id: 'tc1', name: 'search')],
      );

      expect(message.user, equals(ChatUser.assistant));
      expect(message.toolCalls, hasLength(1));
      expect(message.toolCalls.first.name, equals('search'));
      expect(message.id, equals('tc-msg-1'));
    });

    test('create with custom id', () {
      final message = ToolCallMessage.create(
        id: 'tc-msg-id',
        toolCalls: const [ToolCallInfo(id: 'tc1', name: 'search')],
      );

      expect(message.id, equals('tc-msg-id'));
    });

    test('fromExecuted creates message from executed tool calls', () {
      final message = ToolCallMessage.fromExecuted(
        id: 'tc-exec-1',
        toolCalls: const [
          ToolCallInfo(
            id: 'tc1',
            name: 'get_secret_number',
            arguments: '{"name":"alice"}',
            status: ToolCallStatus.completed,
            result: '42',
          ),
          ToolCallInfo(
            id: 'tc2',
            name: 'get_secret_number',
            arguments: '{"name":"bob"}',
            status: ToolCallStatus.failed,
            result: 'Error: unknown name',
          ),
        ],
      );

      expect(message.user, equals(ChatUser.assistant));
      expect(message.id, equals('tc-exec-1'));
      expect(message.toolCalls, hasLength(2));
      expect(message.toolCalls[0].status, equals(ToolCallStatus.completed));
      expect(message.toolCalls[0].result, equals('42'));
      expect(message.toolCalls[1].status, equals(ToolCallStatus.failed));
      expect(message.toolCalls[1].result, equals('Error: unknown name'));
      expect(message.createdAt, isNotNull);
    });

    test('fromExecuted stamps the client clock at creation', () {
      final before = DateTime.timestamp();
      final message = ToolCallMessage.fromExecuted(
        id: 'tc-exec-2',
        toolCalls: const [
          ToolCallInfo(
            id: 'tc1',
            name: 'search',
            status: ToolCallStatus.completed,
            result: 'found',
          ),
        ],
      );
      final after = DateTime.timestamp();

      expect(
        message.createdAt!.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        message.createdAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('GenUiMessage', () {
    test('create with widget and data', () {
      final message = GenUiMessage.create(
        id: 'genui-1',
        widgetName: 'Chart',
        data: const {'value': 42},
      );

      expect(message.user, equals(ChatUser.assistant));
      expect(message.widgetName, equals('Chart'));
      expect(message.data['value'], equals(42));
      expect(message.id, equals('genui-1'));
    });

    test('create with custom id', () {
      final message = GenUiMessage.create(
        id: 'genui-id',
        widgetName: 'Chart',
        data: const {'value': 42},
      );

      expect(message.id, equals('genui-id'));
    });
  });

  group('LoadingMessage', () {
    test('create', () {
      final message = LoadingMessage.create(id: 'loading-1');

      expect(message.user, equals(ChatUser.assistant));
      expect(message.id, equals('loading-1'));
    });

    test('create with custom id', () {
      final message = LoadingMessage.create(id: 'loading-id');

      expect(message.id, equals('loading-id'));
    });
  });

  group('ChatMessage sealed class', () {
    test('different message types with same id are not equal', () {
      final textMsg = TextMessage.create(
        id: 'same-id',
        user: ChatUser.user,
        text: 'Hello',
      );
      final errorMsg = ErrorMessage.create(id: 'same-id', message: 'Error');
      final loadingMsg = LoadingMessage.create(id: 'same-id');

      expect(textMsg, isNot(equals(errorMsg)));
      expect(textMsg, isNot(equals(loadingMsg)));
      expect(errorMsg, isNot(equals(loadingMsg)));
    });

    test('pattern matching on message types', () {
      final messages = <ChatMessage>[
        TextMessage.create(id: 'msg-1', user: ChatUser.user, text: 'Hello'),
        ErrorMessage.create(id: 'err-1', message: 'Error'),
        ToolCallMessage.create(
          id: 'tc-1',
          toolCalls: const [ToolCallInfo(id: 'tc1', name: 'tool')],
        ),
        GenUiMessage.create(
          id: 'genui-1',
          widgetName: 'Widget',
          data: const {},
        ),
        LoadingMessage.create(id: 'loading-1'),
        DroppedEventMessage.create(
          id: 'drop-1',
          source: DropSource.decode,
          reason: 'malformed JSON',
        ),
        NoResponseTile.finished(
          id: 'no-response-run-1',
          thinkingText: '',
        ),
      ];

      final types = messages.map((m) {
        return switch (m) {
          TextMessage() => 'text',
          ErrorMessage() => 'error',
          ToolCallMessage() => 'toolCall',
          GenUiMessage() => 'genUi',
          LoadingMessage() => 'loading',
          DroppedEventMessage() => 'dropped',
          NoResponseTile() => 'noResponse',
        };
      }).toList();

      expect(
        types,
        equals([
          'text',
          'error',
          'toolCall',
          'genUi',
          'loading',
          'dropped',
          'noResponse',
        ]),
      );
    });

    test('extract text from different message types', () {
      final textMsg = TextMessage.create(
        id: 'msg-1',
        user: ChatUser.user,
        text: 'Hello',
      );
      final errorMsg = ErrorMessage.create(
        id: 'err-1',
        message: 'Error occurred',
      );

      String getText(ChatMessage msg) {
        return switch (msg) {
          TextMessage(:final text) => text,
          ErrorMessage(:final errorText) => errorText,
          _ => '',
        };
      }

      expect(getText(textMsg), equals('Hello'));
      expect(getText(errorMsg), equals('Error occurred'));
    });
  });

  group('ToolCallInfo', () {
    test('creates with required fields', () {
      const info = ToolCallInfo(id: 'tc1', name: 'search');

      expect(info.id, equals('tc1'));
      expect(info.name, equals('search'));
      expect(info.arguments, isEmpty);
      expect(info.status, equals(ToolCallStatus.pending));
      expect(info.result, isEmpty);
    });

    test('creates with all fields', () {
      const info = ToolCallInfo(
        id: 'tc1',
        name: 'search',
        arguments: '{"query": "test"}',
        status: ToolCallStatus.completed,
        result: '{"results": []}',
      );

      expect(info.arguments, equals('{"query": "test"}'));
      expect(info.status, equals(ToolCallStatus.completed));
      expect(info.result, equals('{"results": []}'));
    });

    test('copyWith preserves status and result when not passed', () {
      const original = ToolCallInfo(
        id: 'tc1',
        name: 'search',
        status: ToolCallStatus.completed,
        result: 'done',
      );
      final copy = original.copyWith(name: 'new-search');

      expect(copy.status, equals(ToolCallStatus.completed));
      expect(copy.result, equals('done'));
    });

    test('equality by id', () {
      const info1 = ToolCallInfo(id: 'tc1', name: 'search');
      const info2 = ToolCallInfo(
        id: 'tc1',
        name: 'different',
        status: ToolCallStatus.completed,
      );

      expect(info1, equals(info2));
    });

    test('not equal with different id', () {
      const info1 = ToolCallInfo(id: 'tc1', name: 'search');
      const info2 = ToolCallInfo(id: 'tc2', name: 'search');

      expect(info1, isNot(equals(info2)));
    });

    test('hasArguments returns true when arguments are present', () {
      const info = ToolCallInfo(
        id: 'tc1',
        name: 'search',
        arguments: '{"query": "test"}',
      );

      expect(info.hasArguments, isTrue);
    });

    test('hasArguments returns false when arguments are empty', () {
      const info = ToolCallInfo(id: 'tc1', name: 'search');

      expect(info.hasArguments, isFalse);
    });

    test('hasResult returns true when result is present', () {
      const info = ToolCallInfo(
        id: 'tc1',
        name: 'search',
        result: '{"data": []}',
      );

      expect(info.hasResult, isTrue);
    });

    test('hasResult returns false when result is empty', () {
      const info = ToolCallInfo(id: 'tc1', name: 'search');

      expect(info.hasResult, isFalse);
    });
  });
}
