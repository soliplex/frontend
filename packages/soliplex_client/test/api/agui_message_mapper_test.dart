import 'dart:convert';
import 'dart:typed_data';

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
        // A message without parts serializes `content` as a bare string, not
        // a one-element array.
        expect(userMsg.toJson()['content'], equals('Hello, assistant!'));
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

    group('message parts', () {
      // Every part maps to its AG-UI `InputContent` with an inline `data`
      // source and camelCase keys. Two images of different types pin the
      // per-part mime; the leading space in ' then tell me' pins that text
      // runs reach the wire untrimmed.
      test('serializes parts as an ordered multimodal content array', () {
        final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]);
        final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

        final aguiMessages = convertToAgui([
          TextMessage(
            id: 'msg-parts',
            user: ChatUser.user,
            text: 'look at these then tell me',
            createdAt: DateTime.now(),
            parts: [
              const TextPart('look at these'),
              ImagePart(bytes: png, mimeType: 'image/png'),
              ImagePart(bytes: jpeg, mimeType: 'image/jpeg'),
              const TextPart(' then tell me'),
            ],
          ),
        ]);

        expect(aguiMessages, hasLength(1));
        final userMsg = aguiMessages[0] as UserMessage;
        expect(
          userMsg.toJson()['content'],
          equals([
            {'type': 'text', 'text': 'look at these'},
            {
              'type': 'image',
              'source': {
                'type': 'data',
                'value': base64Encode(png),
                'mimeType': 'image/png',
              },
            },
            {
              'type': 'image',
              'source': {
                'type': 'data',
                'value': base64Encode(jpeg),
                'mimeType': 'image/jpeg',
              },
            },
            {'type': 'text', 'text': ' then tell me'},
          ]),
        );
      });

      // An empty text block would be forwarded to the model verbatim rather
      // than skipped, so empty runs must never reach the wire.
      test('omits empty text runs from multimodal content', () {
        final bytes = Uint8List.fromList([0x89, 0x50]);

        final aguiMessages = convertToAgui([
          TextMessage(
            id: 'msg-empty-runs',
            user: ChatUser.user,
            text: 'look',
            createdAt: DateTime.now(),
            parts: [
              const TextPart(''),
              ImagePart(bytes: bytes, mimeType: 'image/png'),
              const TextPart('look'),
              const TextPart(''),
            ],
          ),
        ]);

        final content = (aguiMessages[0] as UserMessage).toJson()['content']
            as List<Map<String, dynamic>>;
        expect(content, hasLength(2));
        expect(content[0]['type'], equals('image'));
        expect(content[1], equals({'type': 'text', 'text': 'look'}));
      });

      // An image-less message keeps exactly the wire shape it has today.
      test('falls back to plain text when parts carry no image', () {
        final aguiMessages = convertToAgui([
          TextMessage(
            id: 'msg-text-only',
            user: ChatUser.user,
            text: 'no images here',
            createdAt: DateTime.now(),
            parts: const [TextPart('no images here')],
          ),
        ]);

        final userMsg = aguiMessages[0] as UserMessage;
        expect(userMsg.toJson()['content'], equals('no images here'));
      });

      // An empty array makes the backend discard the user's turn entirely,
      // with no error anywhere — the one degenerate case that loses data.
      test('never serializes an empty content array', () {
        final aguiMessages = convertToAgui([
          TextMessage(
            id: 'msg-no-parts',
            user: ChatUser.user,
            text: 'still says something',
            createdAt: DateTime.now(),
            parts: const [],
          ),
        ]);

        final userMsg = aguiMessages[0] as UserMessage;
        expect(userMsg.toJson()['content'], equals('still says something'));
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

      test('skips NoResponseTile so it never reaches the wire', () {
        // The synthesized no-response tile is a frontend-only signal.
        // Sending it back to the backend on a continuation run would
        // appear as an empty assistant message — exactly the wire-leak
        // this guard prevents. The exhaustive-switch test catches a
        // missing case at compile time; this exercises the runtime skip.
        final chatMessages = [
          TextMessage(
            id: 'user-1',
            user: ChatUser.user,
            text: 'first',
            createdAt: DateTime.now(),
          ),
          NoResponseTile.cancelled(
            id: 'no-response-run-1',
            thinkingText: 'reasoning preserved on cancel',
          ),
          TextMessage(
            id: 'user-2',
            user: ChatUser.user,
            text: 'second',
            createdAt: DateTime.now(),
          ),
        ];

        final aguiMessages = convertToAgui(chatMessages);

        expect(aguiMessages, hasLength(2));
        expect(aguiMessages[0], isA<UserMessage>());
        expect((aguiMessages[0] as UserMessage).id, equals('user-1'));
        expect(aguiMessages[1], isA<UserMessage>());
        expect((aguiMessages[1] as UserMessage).id, equals('user-2'));
        expect(
          aguiMessages.any((m) => m.id == 'no-response-run-1'),
          isFalse,
        );
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
