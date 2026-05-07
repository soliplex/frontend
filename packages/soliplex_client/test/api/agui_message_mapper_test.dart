import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:test/test.dart';

void main() {
  group('convertToAgui', () {
    group('TextMessage conversion', () {
      test('converts user TextMessage to UserMessage', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-1',
            user: ChatUser.user,
            text: 'Hello, assistant!',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(1));
        expect(aguiMessages[0], isA<UserMessage>());
        final userMsg = aguiMessages[0] as UserMessage;
        expect(userMsg.id, equals('msg-1'));
        expect(userMsg.content, equals('Hello, assistant!'));
      });

      test('converts assistant TextMessage to AssistantMessage', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-2',
            user: ChatUser.assistant,
            text: 'Hello, user!',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(1));
        expect(aguiMessages[0], isA<AssistantMessage>());
        final assistantMsg = aguiMessages[0] as AssistantMessage;
        expect(assistantMsg.id, equals('msg-2'));
        expect(assistantMsg.content, equals('Hello, user!'));
      });

      test('converts system TextMessage to SystemMessage', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-3',
            user: ChatUser.system,
            text: 'System notification',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(1));
        expect(aguiMessages[0], isA<SystemMessage>());
        final systemMsg = aguiMessages[0] as SystemMessage;
        expect(systemMsg.id, equals('msg-3'));
        expect(systemMsg.content, equals('System notification'));
      });
    });

    group('ToolCallMessage conversion', () {
      test('converts ToolCallMessage to AssistantMessage with toolCalls', () {
        final chatMessages = [
          ToolCallMessage(
            id: 'msg-4',
            createdAt: DateTime.now(),
            toolCalls: const [
              ToolCallInfo(
                id: 'tc-1',
                name: 'search',
                arguments: '{"query": "test"}',
                status: ToolCallStatus.completed,
                result: 'Found 3 results',
              ),
              ToolCallInfo(
                id: 'tc-2',
                name: 'calculate',
                arguments: '{"expression": "2+2"}',
                status: ToolCallStatus.completed,
                result: '4',
              ),
            ],
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        // 1 AssistantMessage + 2 ToolMessages for completed tool calls
        expect(aguiMessages, hasLength(3));
        expect(aguiMessages[0], isA<AssistantMessage>());
        final assistantMsg = aguiMessages[0] as AssistantMessage;
        expect(assistantMsg.id, equals('msg-4'));
        expect(assistantMsg.toolCalls, isNotNull);
        expect(assistantMsg.toolCalls, hasLength(2));

        final tc1 = assistantMsg.toolCalls![0];
        expect(tc1.id, equals('tc-1'));
        expect(tc1.function.name, equals('search'));
        expect(tc1.function.arguments, equals('{"query": "test"}'));

        final tc2 = assistantMsg.toolCalls![1];
        expect(tc2.id, equals('tc-2'));
        expect(tc2.function.name, equals('calculate'));
        expect(tc2.function.arguments, equals('{"expression": "2+2"}'));

        // Verify ToolMessages
        expect(aguiMessages[1], isA<ToolMessage>());
        expect(aguiMessages[2], isA<ToolMessage>());
      });

      test('includes ToolMessage for completed tool calls', () {
        final chatMessages = [
          ToolCallMessage(
            id: 'msg-4',
            createdAt: DateTime.now(),
            toolCalls: const [
              ToolCallInfo(
                id: 'tc-1',
                name: 'search',
                arguments: '{"query": "test"}',
                status: ToolCallStatus.completed,
                result: 'Found 3 results',
              ),
            ],
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        // Should produce AssistantMessage + ToolMessage
        expect(aguiMessages, hasLength(2));
        expect(aguiMessages[0], isA<AssistantMessage>());
        expect(aguiMessages[1], isA<ToolMessage>());

        final toolMsg = aguiMessages[1] as ToolMessage;
        expect(toolMsg.toolCallId, equals('tc-1'));
        expect(toolMsg.content, equals('Found 3 results'));
      });

      test('skips ToolMessage for pending tool calls', () {
        final chatMessages = [
          ToolCallMessage(
            id: 'msg-4',
            createdAt: DateTime.now(),
            toolCalls: const [
              ToolCallInfo(
                id: 'tc-1',
                name: 'search',
                arguments: '{"query": "test"}',
              ),
            ],
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        // Only AssistantMessage, no ToolMessage for pending
        expect(aguiMessages, hasLength(1));
        expect(aguiMessages[0], isA<AssistantMessage>());
      });
    });

    group('GenUiMessage conversion', () {
      test(
        'converts GenUiMessage to AssistantMessage with descriptive content',
        () {
          final chatMessages = [
            GenUiMessage(
              id: 'msg-5',
              createdAt: DateTime.now(),
              widgetName: 'WeatherCard',
              data: const {'temperature': 72, 'condition': 'sunny'},
            ),
          ];

          final aguiMessages = convertToAgui(chatMessages);

          expect(aguiMessages, hasLength(1));
          expect(aguiMessages[0], isA<AssistantMessage>());
          final assistantMsg = aguiMessages[0] as AssistantMessage;
          expect(assistantMsg.id, equals('msg-5'));
          expect(assistantMsg.content, contains('WeatherCard'));
        },
      );
    });

    group('skipped message types', () {
      test('skips ErrorMessage', () {
        final chatMessages = [
          ErrorMessage(
            id: 'msg-6',
            createdAt: DateTime.now(),
            errorText: 'Something went wrong',
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, isEmpty);
      });

      test('skips LoadingMessage', () {
        final chatMessages = [
          LoadingMessage(id: 'msg-7', createdAt: DateTime.now()),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, isEmpty);
      });

      test('skips DroppedEventMessage', () {
        final chatMessages = [
          DroppedEventMessage(
            id: 'drop-1',
            createdAt: DateTime.now(),
            source: DropSource.decode,
            reason: 'unknown event type',
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, isEmpty);
      });
    });

    group('mixed message list', () {
      test('converts mixed message types preserving order', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-1',
            user: ChatUser.user,
            text: 'Search for something',
            createdAt: DateTime.now(),
          ),
          ToolCallMessage(
            id: 'msg-2',
            createdAt: DateTime.now(),
            toolCalls: const [
              ToolCallInfo(
                id: 'tc-1',
                name: 'search',
                arguments: '{}',
                status: ToolCallStatus.completed,
                result: 'Results',
              ),
            ],
          ),
          TextMessage(
            id: 'msg-3',
            user: ChatUser.assistant,
            text: 'Here are your results',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        // msg-1 (UserMessage) + msg-2 (AssistantMessage) + tc-1 (ToolMessage)
        // + msg-3 (AssistantMessage) = 4 messages
        expect(aguiMessages, hasLength(4));
        expect(aguiMessages[0], isA<UserMessage>());
        expect(aguiMessages[1], isA<AssistantMessage>());
        expect(aguiMessages[2], isA<ToolMessage>());
        expect(aguiMessages[3], isA<AssistantMessage>());
      });

      test('filters out transient messages while keeping others', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-1',
            user: ChatUser.user,
            text: 'Hello',
            createdAt: DateTime.now(),
          ),
          LoadingMessage(id: 'loading-1', createdAt: DateTime.now()),
          ErrorMessage(
            id: 'error-1',
            createdAt: DateTime.now(),
            errorText: 'Error',
          ),
          TextMessage(
            id: 'msg-2',
            user: ChatUser.assistant,
            text: 'Response',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(2));
        expect(aguiMessages[0], isA<UserMessage>());
        expect(aguiMessages[1], isA<AssistantMessage>());
      });
    });

    group('edge cases', () {
      test('handles empty list', () {
        final aguiMessages = convertToAgui([]);

        expect(aguiMessages, isEmpty);
      });

      test('handles empty text content', () {
        final chatMessages = [
          TextMessage(
            id: 'msg-1',
            user: ChatUser.user,
            text: '',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(1));
        expect((aguiMessages[0] as UserMessage).content, equals(''));
      });

      test('handles empty tool call arguments', () {
        final chatMessages = [
          ToolCallMessage(
            id: 'msg-1',
            createdAt: DateTime.now(),
            toolCalls: const [
              ToolCallInfo(
                id: 'tc-1',
                name: 'noArgs',
                status: ToolCallStatus.completed,
                result: 'Done',
              ),
            ],
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(2));
        final assistantMsg = aguiMessages[0] as AssistantMessage;
        expect(assistantMsg.toolCalls![0].function.arguments, equals('{}'));
      });
    });
  });
}
