import 'dart:convert';
import 'dart:typed_data';

import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:test/test.dart';

void main() {
  /// The wire form of each user message, in order.
  List<Message> convert(List<TextMessage> messages) => messages
      .fold(Conversation.empty(threadId: 't'), appendUserMessage)
      .transcript
      .messages;

  group('appendUserMessage', () {
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

        final aguiMessages = convert(chatMessages);

        expect(aguiMessages, hasLength(1));
        expect(aguiMessages[0], isA<UserMessage>());
        final userMsg = aguiMessages[0] as UserMessage;
        expect(userMsg.id, equals('msg-1'));
        expect(userMsg.content, equals('Hello, assistant!'));
        // A message without parts serializes `content` as a bare string, not
        // a one-element array.
        expect(userMsg.toJson()['content'], equals('Hello, assistant!'));
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

        final aguiMessages = convert([
          TextMessage(
            id: 'msg-parts',
            user: ChatUser.user,
            text: 'look at these then tell me',
            createdAt: DateTime.now(),
            parts: [
              const TextPart('look at these'),
              ImagePart(bytes: png, mimeType: 'image/png', number: 1),
              ImagePart(bytes: jpeg, mimeType: 'image/jpeg', number: 2),
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
            {'type': 'text', 'text': 'Image 1:'},
            {
              'type': 'image',
              'source': {
                'type': 'data',
                'value': base64Encode(png),
                'mimeType': 'image/png',
              },
              'metadata': {'soliplex_image_number': 1},
            },
            {'type': 'text', 'text': 'Image 2:'},
            {
              'type': 'image',
              'source': {
                'type': 'data',
                'value': base64Encode(jpeg),
                'mimeType': 'image/jpeg',
              },
              'metadata': {'soliplex_image_number': 2},
            },
            {'type': 'text', 'text': ' then tell me'},
          ]),
        );
      });

      // An empty text block would be forwarded to the model verbatim rather
      // than skipped, so empty runs must never reach the wire.
      test('omits empty text runs from multimodal content', () {
        final bytes = Uint8List.fromList([0x89, 0x50]);

        final aguiMessages = convert([
          TextMessage(
            id: 'msg-empty-runs',
            user: ChatUser.user,
            text: 'look',
            createdAt: DateTime.now(),
            parts: [
              const TextPart(''),
              ImagePart(bytes: bytes, mimeType: 'image/png', number: 1),
              const TextPart('look'),
              const TextPart(''),
            ],
          ),
        ]);

        final content = (aguiMessages[0] as UserMessage).toJson()['content']
            as List<Map<String, dynamic>>;
        expect(content, hasLength(3));
        expect(content[0], equals({'type': 'text', 'text': 'Image 1:'}));
        expect(content[1]['type'], equals('image'));
        expect(content[2], equals({'type': 'text', 'text': 'look'}));
      });

      // An image-less message keeps exactly the wire shape it has today.
      test('falls back to plain text when parts carry no image', () {
        final aguiMessages = convert([
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

      // The whole conversation is re-sent on every run, so a message rebuilt
      // from history goes back over the wire. A placeholder has no content to
      // send, and reaching the converter with one would throw and take the
      // next run with it.
      test('drops a missing attachment but keeps the images beside it', () {
        final bytes = Uint8List.fromList([0x89, 0x50]);

        final aguiMessages = convert([
          TextMessage.fromParts(
            id: 'msg-rehydrated',
            parts: [
              const TextPart('compare '),
              ImagePart(bytes: bytes, mimeType: 'image/png', number: 1),
              const MissingAttachmentPart(
                reason: MissingAttachmentReason.undecodable,
                number: 2,
              ),
            ],
          ),
        ]);

        final content = (aguiMessages[0] as UserMessage).toJson()['content']
            as List<Map<String, dynamic>>;
        expect(content, hasLength(3));
        expect(content[0], equals({'type': 'text', 'text': 'compare '}));
        expect(content[1], equals({'type': 'text', 'text': 'Image 1:'}));
        expect(content[2]['type'], equals('image'));
      });

      // Nothing sendable is left once the placeholder is dropped, so the
      // multimodal array would be text-only — which buys nothing over the bare
      // string and must not become an empty array either.
      test('falls back to plain text when only a missing attachment remains',
          () {
        final aguiMessages = convert([
          TextMessage.fromParts(
            id: 'msg-all-missing',
            parts: const [
              TextPart('look at this'),
              MissingAttachmentPart(
                reason: MissingAttachmentReason.remoteSource,
              ),
            ],
          ),
        ]);

        final userMsg = aguiMessages[0] as UserMessage;
        expect(userMsg.toJson()['content'], equals('look at this'));
      });

      // An empty array makes the backend discard the user's turn entirely,
      // with no error anywhere — the one degenerate case that loses data.
      test('never serializes an empty content array', () {
        final aguiMessages = convert([
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

    group('image numbering', () {
      final bytes = Uint8List.fromList([0x89, 0x50]);
      ImagePart image(int number) =>
          ImagePart(bytes: bytes, mimeType: 'image/png', number: number);

      List<String> labelsOf(List<Message> messages) => [
            for (final message in messages)
              if (message is UserMessage)
                ...?(message.toJson()['content'] as List?)
                    ?.cast<Map<String, Object?>>()
                    .where((part) => part['type'] == 'text')
                    .map((part) => part['text']! as String)
                    .where((text) => text.startsWith('Image ')),
          ];

      // Each image is announced by the number it carries, not one counted
      // here — the part's number is what the model was told and what the
      // bubble shows.
      test('labels each image with the number it carries', () {
        final agui = convert([
          TextMessage.fromParts(
            id: 'm1',
            parts: [const TextPart('these'), image(7), image(8)],
          ),
          TextMessage.fromParts(
            id: 'm2',
            parts: [const TextPart('and this'), image(9)],
          ),
        ]);

        expect(labelsOf(agui), equals(['Image 7:', 'Image 8:', 'Image 9:']));
      });

      // The gap the slot leaves is harmless because a label is absolute: the
      // images that remain still answer to the numbers they were given, so
      // nothing needs to be said about the one that is gone.
      test('leaves a gap where an attachment cannot be sent', () {
        final agui = convert([
          TextMessage.fromParts(
            id: 'm1',
            parts: [
              image(1),
              const MissingAttachmentPart(
                reason: MissingAttachmentReason.remoteSource,
                number: 2,
              ),
              image(3),
            ],
          ),
        ]);

        expect(labelsOf(agui), equals(['Image 1:', 'Image 3:']));
        final content = (agui[0] as UserMessage).toJson()['content']! as List;
        expect(
          content.where((part) => part is Map && part['type'] == 'image'),
          hasLength(2),
        );
      });

      // An image nothing has ever named is sent as it is. Inventing a label
      // would tell the model a name no earlier turn used.
      test('sends an unnumbered image without a label', () {
        final agui = convert([
          TextMessage.fromParts(
            id: 'm1',
            parts: [
              const TextPart('look '),
              ImagePart(bytes: bytes, mimeType: 'image/png'),
            ],
          ),
        ]);

        expect(labelsOf(agui), isEmpty);
        final content = (agui[0] as UserMessage).toJson()['content']! as List;
        expect(content, hasLength(2));
        expect((content[1] as Map).containsKey('metadata'), isFalse);
      });

      // The backend keeps what was sent, so a label comes back as a text part.
      // Left in, it would render in the user's sentence and be labelled again
      // on the next send.
      test('strips its own labels when reading content back', () {
        final agui = convert([
          TextMessage.fromParts(
            id: 'm1',
            parts: [const TextPart('look at '), image(4)],
          ),
        ]);
        final content = (agui[0] as UserMessage).toJson()['content'];

        final read = readUserMessageContent(content, logContext: 'test');

        expect(read.parts, hasLength(2));
        expect((read.parts![0] as TextPart).text, equals('look at '));
        expect(read.parts![1], isA<ImagePart>());
        expect(read.text, equals('look at '));
      });

      // The number the block carries is what makes stripping safe. Identical
      // words the user typed, in front of an image this client never numbered,
      // are theirs and must survive.
      test("keeps a user's own text that looks like a label", () {
        final read = readUserMessageContent(
          [
            {'type': 'text', 'text': 'Image 1:'},
            {
              'type': 'image',
              'source': {
                'type': 'data',
                'value': base64Encode(bytes),
                'mimeType': 'image/png',
              },
            },
          ],
          logContext: 'test',
        );

        expect(read.parts, hasLength(2));
        expect((read.parts![0] as TextPart).text, equals('Image 1:'));
      });
    });
  });
}
