import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/attachment_numbering.dart';

void main() {
  ImagePart image() =>
      ImagePart(bytes: Uint8List.fromList([0x89]), mimeType: 'image/png');

  TextMessage user(String id, List<MessagePart> parts) =>
      TextMessage.fromParts(id: id, parts: parts);

  TextMessage assistant(String id) => TextMessage(
        id: id,
        user: ChatUser.assistant,
        text: 'a reply',
        createdAt: DateTime(2026),
      );

  // The offset is what makes a number name one image for as long as the thread
  // lasts. Restarting per message would give two images the same number.
  test('accumulates across messages', () {
    final offsets = attachmentOffsets([
      user('m1', [const TextPart('these'), image(), image()]),
      assistant('a1'),
      user('m2', [const TextPart('and this'), image()]),
    ]);

    expect(offsets, equals([0, 2, 2]));
  });

  // A slot that could not be rebuilt still spends its number, so the images
  // after it keep the ones they were already given.
  test('counts a missing attachment as a slot', () {
    final offsets = attachmentOffsets([
      user('m1', [
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.remoteSource,
        ),
      ]),
      user('m2', [image()]),
    ]);

    expect(offsets, equals([0, 2]));
  });

  // Only user messages carry attachments, but the list holds every kind of
  // message; a non-text one must not throw or shift the count.
  test('ignores messages that carry no parts', () {
    final offsets = attachmentOffsets([
      user('m1', [image()]),
      LoadingMessage(id: 'l1', createdAt: DateTime(2026)),
      user('m2', [image()]),
    ]);

    expect(offsets, equals([0, 1, 1]));
  });
}
