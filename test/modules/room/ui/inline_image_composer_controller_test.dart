import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/composer_draft.dart';
import 'package:soliplex_frontend/src/modules/room/ui/inline_image_composer_controller.dart';

/// An image whose first byte identifies it, so a test can say which image
/// survived an edit.
ImagePart _image(int id) =>
    ImagePart(bytes: Uint8List.fromList([id]), mimeType: 'image/png');

/// The identifying byte of every image the composer would send, in order.
List<int> _sentImageIds(InlineImageComposerController controller) =>
    (controller.sendableParts() ?? const <MessagePart>[])
        .whereType<ImagePart>()
        .map((part) => part.bytes.first)
        .toList();

/// Types [text] over the current selection, as the platform would.
void _type(TextEditingController controller, String text) {
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : controller.text.length;
  final end = selection.isValid ? selection.end : controller.text.length;
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// Deletes `[start, end)`, as a selection delete or a backspace would.
void _delete(TextEditingController controller, int start, int end) {
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(start, end, ''),
    selection: TextSelection.collapsed(offset: start),
  );
}

void _caret(TextEditingController controller, int offset) =>
    controller.value = controller.value
        .copyWith(selection: TextSelection.collapsed(offset: offset));

InlineImageComposerController _controller() {
  final controller = InlineImageComposerController();
  addTearDown(controller.dispose);
  return controller;
}

Widget _composer(InlineImageComposerController controller) => MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: TextField(controller: controller, maxLines: 5),
      ),
    );

void main() {
  group('send split', () {
    test('splits the text at each image into ordered parts', () {
      final controller = _controller();
      _type(controller, 'look at ');
      controller.insertImagesAtCaret([_image(1)]);
      _type(controller, ' and tell me');

      final parts = controller.sendableParts();

      expect(parts, hasLength(3));
      expect((parts![0] as TextPart).text, 'look at ');
      expect((parts[1] as ImagePart).bytes.first, 1);
      expect((parts[2] as TextPart).text, ' and tell me');
    });

    test('emits no text part between adjacent images', () {
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1), _image(2)]);

      final parts = controller.sendableParts();

      expect(parts, hasLength(2));
      expect(parts!.whereType<TextPart>(), isEmpty);
      expect(_sentImageIds(controller), [1, 2]);
    });

    test('clearing the composer releases every image it held', () {
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1), _image(2)]);

      controller.clear();

      expect(
        controller.heldImageCount,
        isZero,
        reason: 'a sent or abandoned composer must not retain photo bytes',
      );
    });

    test('refuses to send a composer holding only whitespace', () {
      final controller = _controller();
      expect(controller.sendableParts(), isNull);

      _type(controller, '   ');

      expect(controller.sendableParts(), isNull);
      expect(controller.canSend, isFalse);
    });

    test('appends when the selection reaches past the end of the text', () {
      // A picker runs for seconds; the caret it was opened with can be stale
      // by the time bytes come back, and replaceRange throws on that.
      final controller = _controller();
      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection(baseOffset: 0, extentOffset: 99),
      );

      controller.insertImagesAtCaret([_image(1)]);

      expect(_sentImageIds(controller), [1]);
      expect(controller.sendableParts(), hasLength(2));
    });

    test('sends an image with no text at all', () {
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1)]);

      // TextMessage.fromParts throws on a payload carrying neither, so this is
      // the boundary the empty-composer guard must not overreach into.
      expect(controller.sendableParts(), hasLength(1));
      expect(controller.canSend, isTrue);
    });
  });

  group('characters the composer did not mint', () {
    test('a Private Use Area character the user typed is text', () {
      // U+F8FF is the Apple logo, and a terminal's Nerd Font glyphs sit beside
      // it. Reading one as an image puts an error chip over the user's own
      // character and disables the send with no way to comply.
      final controller = _controller();

      _type(controller, 'made on a  laptop');

      expect(controller.hasPlaceholderImage, isFalse);
      expect(controller.canSend, isTrue);
      expect(controller.sendableParts(), hasLength(1));
    });

    test('an image still reads as one beside a character like it', () {
      final controller = _controller();

      _type(controller, ' next to ');
      controller.insertImagesAtCaret([_image(1)]);

      expect(_sentImageIds(controller), [1]);
      expect(controller.contents.whereType<ComposerImageSlot>(), hasLength(1));
    });
  });

  group('image identity survives editing', () {
    test('deleting the first of two adjacent images keeps the second', () {
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1), _image(2)]);

      _delete(controller, 0, 1);

      expect(_sentImageIds(controller), [2]);
    });

    test('deleting the second of two adjacent images keeps the first', () {
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1), _image(2)]);

      _delete(controller, 1, 2);

      expect(_sentImageIds(controller), [1]);
    });

    test('cutting an image and pasting it elsewhere moves that image', () {
      final controller = _controller();
      _type(controller, 'a');
      controller.insertImagesAtCaret([_image(1), _image(2)]);

      final cut = controller.text[1];
      _delete(controller, 1, 2);
      _caret(controller, controller.text.length);
      _type(controller, cut);

      expect(_sentImageIds(controller), [2, 1]);
    });
  });

  group('draft across re-auth', () {
    const draftText = 'look at ';
    const draftTail = ' and tell me';

    String draftOf(List<MessagePart> parts) => encodeComposerDraft(parts);

    test('a draft carries each image position and none of its bytes', () {
      final draft = draftOf([
        const TextPart(draftText),
        _image(1),
        const TextPart(draftTail),
      ]);

      expect(draft, '$draftText$composerDraftImageMarker$draftTail');
      // persistComposerDraft drops a whitespace-only draft without writing,
      // leaving an older one in the slot to be restored later, so an image
      // with no caption has to survive that check on the marker alone.
      expect(draftOf([_image(1)]).trim(), isNotEmpty);
    });

    test("a marker in the user's own text is not restored as an image", () {
      // A copy out of a PDF carries U+FFFC. Restoring it as a placeholder
      // would report an image the user never attached, and block the send.
      final controller = _controller();

      controller.restoreDraft(
        draftOf([TextPart('see ${composerDraftImageMarker}below')]),
      );

      expect(controller.hasPlaceholderImage, isFalse);
      expect(controller.canSend, isTrue);
    });

    test('restoring puts an unavailable placeholder where each image was', () {
      final controller = _controller();

      controller.restoreDraft(
        draftOf([
          const TextPart(draftText),
          _image(1),
          const TextPart(draftTail),
        ]),
      );

      expect(controller.contents, [
        isA<ComposerTextRun>().having((run) => run.text, 'text', draftText),
        isA<ComposerImageSlot>()
            .having((slot) => slot.image, 'image', isA<UnavailableImage>()),
        isA<ComposerTextRun>().having((run) => run.text, 'text', draftTail),
      ]);
    });

    test('refuses to send until the unavailable image is removed', () {
      final controller = _controller();
      controller.restoreDraft(
        draftOf([const TextPart(draftText), _image(1)]),
      );

      // Sending would drop the placeholder and alter what the user wrote.
      expect(controller.sendableParts(), isNull);
      expect(controller.hasPlaceholderImage, isTrue);

      _delete(controller, draftText.length, draftText.length + 1);

      expect(controller.sendableParts(), hasLength(1));
    });
  });

  group('placeholder chips', () {
    testWidgets('a token whose image was released renders as missing',
        (tester) async {
      // What an undo after a send leaves: the character comes back, the bytes
      // were let go with the sent message.
      final controller = _controller();
      controller.insertImagesAtCaret([_image(1)]);
      final token = controller.text;
      controller.clear();
      controller.text = 'a${token}b';

      await tester.pumpWidget(_composer(controller));

      expect(find.text('missing'), findsOneWidget);
      expect(controller.canSend, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an unavailable image removes it', (tester) async {
      final controller = _controller();
      controller.restoreDraft('a${composerDraftImageMarker}b');

      await tester.pumpWidget(_composer(controller));
      await tester.tap(find.byIcon(Icons.image_not_supported_outlined));
      await tester.pump();

      expect(controller.text, 'ab');
      expect(controller.hasPlaceholderImage, isFalse);
      expect(controller.canSend, isTrue);
    });
  });
}
