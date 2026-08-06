import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/attachment_pill.dart';
import 'package:soliplex_frontend/src/modules/room/ui/copy_button.dart';
import 'package:soliplex_frontend/src/modules/room/ui/feedback_buttons.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_caption.dart';
import 'package:soliplex_frontend/src/modules/room/ui/paged_zoomable_images.dart';
import 'package:soliplex_frontend/src/modules/room/ui/text_message_tile.dart';
import 'package:soliplex_frontend/src/shared/zoomable_image.dart';

Widget _wrap(Widget child, {MessageExpansions? store}) => ProviderScope(
      overrides: [
        messageExpansionsProvider
            .overrideWithValue(store ?? MessageExpansions()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  setUp(() {
    // Decode results outlive the test that produced them: the binding's image
    // cache is not reset between tests in a file, so a failed decode in one
    // test makes a later test's sound image fail too. Cleared so no test's
    // result depends on the ones that ran before it.
    imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('user message shows copy button but no feedback buttons',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: '1',
          user: ChatUser.user,
          createdAt: DateTime(2026),
          text: 'Hello',
        ),
      ),
    ));

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsNothing);
  });

  testWidgets('shows a timestamp caption when createdAt is set',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'cap-1',
          user: ChatUser.user,
          createdAt: DateTime(2020, 3, 3, 9, 3),
          text: 'Hello',
        ),
      ),
    ));

    expect(find.byType(MessageCaption), findsOneWidget);
    expect(find.text('Mar 3, 2020 · 9:03 AM'), findsOneWidget);
  });

  testWidgets('omits the caption when createdAt is null', (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'cap-2',
          user: ChatUser.assistant,
          createdAt: null,
          text: 'Streaming…',
        ),
      ),
    ));

    expect(find.byType(MessageCaption), findsNothing);
  });

  testWidgets('assistant bubble markdown defers selection to the area',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'a1',
          user: ChatUser.assistant,
          createdAt: DateTime(2020),
          text: 'reply',
        ),
      ),
    ));

    final md = tester.widget<FlutterMarkdownPlusRenderer>(
      find.byType(FlutterMarkdownPlusRenderer),
    );
    expect(md.selectable, isFalse);
  });

  testWidgets('user bubble is a plain Text, not SelectableText',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'u1',
          user: ChatUser.user,
          createdAt: DateTime(2020),
          text: 'Hello',
        ),
      ),
    ));

    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('assistant message shows copy button and feedback buttons',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: '2',
          user: ChatUser.assistant,
          createdAt: DateTime(2026),
          text: 'Hi there',
        ),
        runId: 'run-1',
        onFeedbackSubmit: (_, __) {},
      ),
    ));

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsOneWidget);
  });

  testWidgets('assistant message without feedback callback shows only copy',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: '3',
          user: ChatUser.assistant,
          createdAt: DateTime(2026),
          text: 'Hi there',
        ),
      ),
    ));

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsNothing);
  });

  testWidgets('thinking block shows copy button', (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: '4',
          user: ChatUser.assistant,
          createdAt: DateTime(2026),
          text: 'Response',
          thinkingText: 'Let me think about this...',
        ),
      ),
    ));

    // One CopyButton for the message, one for the thinking block
    expect(find.byType(CopyButton), findsNWidgets(2));
  });

  testWidgets('fallback thinking block persists expansion across remount',
      (tester) async {
    // Fallback _ThinkingBlock wires ExpansionTile.initiallyExpanded +
    // onExpansionChanged to the store. A remount (which destroys
    // ExpansionTile's internal State) must re-seed from the store.
    final store = MessageExpansions();
    final msg = TextMessage(
      id: 'msg-5',
      user: ChatUser.assistant,
      createdAt: DateTime(2026),
      text: 'Response',
      thinkingText: 'Deep thought',
    );

    Widget tree(Key parentKey) => _wrap(
          KeyedSubtree(
            key: parentKey,
            child: TextMessageTile(roomId: 'r', message: msg),
          ),
          store: store,
        );

    await tester.pumpWidget(tree(const ValueKey('A')));
    expect(find.text('Deep thought'), findsNothing);

    await tester.tap(find.text('Thinking...'));
    await tester.pumpAndSettle();
    expect(find.text('Deep thought'), findsOneWidget);

    await tester.pumpWidget(tree(const ValueKey('B')));
    await tester.pumpAndSettle();
    expect(find.text('Deep thought'), findsOneWidget);
  });

  testWidgets('fallback thinking block persists collapse across remount',
      (tester) async {
    // Mirror of the expand-persists test: collapse (false) must also be
    // written to the store so a remount re-seeds as collapsed.
    final store = MessageExpansions();
    final msg = TextMessage(
      id: 'msg-6',
      user: ChatUser.assistant,
      createdAt: DateTime(2026),
      text: 'Response',
      thinkingText: 'Deep thought',
    );

    Widget tree(Key parentKey) => _wrap(
          KeyedSubtree(
            key: parentKey,
            child: TextMessageTile(roomId: 'r', message: msg),
          ),
          store: store,
        );

    await tester.pumpWidget(tree(const ValueKey('A')));
    await tester.tap(find.text('Thinking...'));
    await tester.pumpAndSettle();
    expect(find.text('Deep thought'), findsOneWidget);

    await tester.tap(find.text('Thinking...'));
    await tester.pumpAndSettle();
    expect(find.text('Deep thought'), findsNothing);
    expect(store.forMessage('r', 'msg-6').thinkingExpanded, isFalse);

    await tester.pumpWidget(tree(const ValueKey('B')));
    await tester.pumpAndSettle();
    expect(find.text('Deep thought'), findsNothing);
  });

  testWidgets('empty assistant message shows a shimmer placeholder',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'empty-1',
          user: ChatUser.assistant,
          createdAt: DateTime(2026),
          text: '',
        ),
      ),
    ));

    expect(find.byType(SoliplexShimmer), findsOneWidget);
  });

  group('a user message carrying image parts', () {
    // A real 1x1 PNG rather than arbitrary bytes, so these tests exercise the
    // decoding path instead of the failure placeholder.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      '//8/AwAI/AL+XJ/PIAAAAABJRU5ErkJggg==',
    );

    ImagePart image() => ImagePart(bytes: pngBytes, mimeType: 'image/png');

    Widget tile(List<MessagePart> parts, {int attachmentsBefore = 0}) => _wrap(
          TextMessageTile(
            roomId: 'r',
            message: TextMessage.fromParts(
              id: 'parts-1',
              parts: parts,
              createdAt: DateTime(2026),
            ),
            attachmentsBefore: attachmentsBefore,
          ),
        );

    /// The bubble's rich text — the only `Text.rich` in the tile.
    TextSpan bubbleSpan(WidgetTester tester) {
      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .singleWhere((t) => t.textSpan != null);
      return rich.textSpan! as TextSpan;
    }

    testWidgets('keeps each attachment its place in the sentence',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('read the code in '),
        image(),
        const TextPart(' and reply'),
      ]));

      final children = bubbleSpan(tester).children!;
      expect(children, hasLength(3));
      expect((children[0] as TextSpan).text, equals('read the code in '));
      expect(children[1], isA<WidgetSpan>());
      expect((children[2] as TextSpan).text, equals(' and reply'));
      // The pill holds the place; the image itself is in the row above.
      expect(find.byType(AttachmentPill), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    // Tapping the badge must reach the tile beneath it. A `Stack` hit-tests in
    // reverse paint order and a `RenderParagraph` always reports a hit, so
    // without an `IgnorePointer` the digits are a dead patch in the middle of a
    // 48 px tap target.
    testWidgets('tapping the number badge still opens the image',
        (tester) async {
      await tester.pumpWidget(tile([const TextPart('look '), image()]));

      // The badge sits in the tile's top-left corner.
      await tester.tapAt(
        tester.getTopLeft(find.byType(Image)) + const Offset(6, 6),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PagedZoomableImages), findsOneWidget);
    });

    // Order is the whole cross-reference: the nth pill is the nth tile only if
    // a slot that cannot be shown still takes both.
    testWidgets('gives a missing attachment a tile and a pill like any other',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('compare '),
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.unsupportedType,
          mimeType: 'audio/mpeg',
        ),
        const TextPart(' with '),
        image(),
      ]));

      expect(find.byType(AttachmentPill), findsNWidgets(3));
      // Two decodable images plus the slot that degrades, all three in the row.
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    // A number is only worth showing if it is the same one the model was told,
    // so it has to continue the thread's sequence rather than start at 1 in
    // every message.
    testWidgets('numbers attachments from the thread, not from one',
        (tester) async {
      await tester.pumpWidget(
        tile(
          [const TextPart('compare '), image(), image()],
          attachmentsBefore: 6,
        ),
      );

      // Once under the tile, once in the pill, for each of the two.
      expect(find.text('7'), findsNWidgets(2));
      expect(find.text('8'), findsNWidgets(2));
      expect(find.text('1'), findsNothing);
    });

    // The slot spends its number even though nothing can be shown or sent for
    // it, so the image after it is not renumbered into a number already used.
    testWidgets('a missing attachment spends its number', (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('compare '),
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.remoteSource,
        ),
        image(),
      ]));

      expect(find.text('1'), findsNWidgets(2));
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('3'), findsNWidgets(2));
    });

    // A pill holds an attachment's place in a sentence. With nothing written
    // around them there is no sentence, and pills under the tiles they name
    // would be the same row twice.
    testWidgets('an attachment-only message renders no pills', (tester) async {
      await tester.pumpWidget(tile([image(), image()]));

      expect(find.byType(AttachmentPill), findsNothing);
      // The tiles and their badges still render.
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    // The pill is small and the sentence around it reads normally, so its
    // colour is the only thing marking a slot the message carried but cannot
    // show. A neutral one skims past.
    testWidgets('a missing attachment is marked as an error', (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('listen to '),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.remoteSource,
        ),
      ]));

      final pill = tester.widget<AttachmentPill>(find.byType(AttachmentPill));
      expect(pill.isError, isTrue);
    });

    // Pill position counts attachments; the pager counts images. A missing
    // attachment between them makes those diverge — slot 3 is page 2 — so an
    // off-by-one that opened the wrong photo cannot pass here.
    testWidgets("tapping the last image's pill opens the pager at that image",
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('compare '),
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.remoteSource,
        ),
        const TextPart(' with '),
        image(),
      ]));

      expect(find.byType(ZoomableImage), findsNothing);

      await tester.tap(find.byType(AttachmentPill).last);
      await tester.pumpAndSettle();

      final pager =
          tester.widget<PagedZoomableImages>(find.byType(PagedZoomableImages));
      expect(pager.initialIndex, equals(1));
      expect(pager.itemCount, equals(2));
    });

    // One slot per ImagePart, each laid out at the tap target rather than at
    // the image's intrinsic size, so a bubble of photos stays a sentence.
    testWidgets('gives every image its own tap-target slot', (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('rank these '),
        image(),
        image(),
        image(),
        image(),
        const TextPart(' by sharpness please'),
      ]));

      expect(find.byType(Image), findsNWidgets(4));
      expect(tester.getSize(find.byType(Image).first), const Size(48, 48));
    });

    // The pager pages over the images alone, so its index counts images while
    // the bubble counts parts. A placeholder between the two makes those
    // diverge — index 1 against slot 3 — so an off-by-one that opened the wrong
    // photo cannot pass here.
    testWidgets('tapping the second image opens the pager at that image',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('compare '),
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.remoteSource,
        ),
        const TextPart(' with '),
        image(),
      ]));

      expect(find.byType(ZoomableImage), findsNothing);

      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();

      // The starting page is read off the pager itself. Asserting on which
      // ZoomableImage happens to be built would instead rest on how many
      // neighbours PageView keeps alive, which is not our decision to pin.
      final pager =
          tester.widget<PagedZoomableImages>(find.byType(PagedZoomableImages));
      expect(pager.initialIndex, equals(1));
      expect(pager.itemCount, equals(2));
    });

    // Bytes that are not a decodable image at all. The slot keeps its size so
    // the sentence does not reflow, and the surrounding text still reads.
    testWidgets('an image whose bytes will not decode shows a placeholder',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('look at '),
        ImagePart(
          bytes: Uint8List.fromList(const [1, 2, 3, 4]),
          mimeType: 'image/png',
        ),
      ]));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(bubbleSpan(tester).children, hasLength(2));
      // The failed slot keeps the same footprint as a decoded one, so the
      // sentence does not reflow when an image turns out to be unreadable.
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byIcon(Icons.broken_image),
                matching: find.byType(Container),
              )
              .first,
        ),
        const Size(48, 48),
      );
    });

    // An attachment history could not rebuild keeps its place in the sentence
    // instead of vanishing, so the bubble reports what it was sent with rather
    // than reading as though it never carried anything.
    testWidgets('a missing attachment holds its slot beside a readable image',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('compare '),
        image(),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.unsupportedType,
          mimeType: 'audio/mpeg',
        ),
        const TextPart(' please'),
      ]));

      final children = bubbleSpan(tester).children!;
      expect(children, hasLength(4));
      expect(children[1], isA<WidgetSpan>());
      expect(children[2], isA<WidgetSpan>());
      // The readable image still renders; only the unreadable slot degrades.
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    // The glyph carries the meaning visually, so the announcement is all a
    // screen reader user gets — it has to say what kind of thing is missing,
    // not merely that something is. Asserting the type reaches the label, not
    // the wording around it.
    testWidgets('a missing attachment names its kind for a screen reader',
        (tester) async {
      await tester.pumpWidget(tile([
        const TextPart('listen to '),
        const MissingAttachmentPart(
          reason: MissingAttachmentReason.unsupportedType,
          mimeType: 'audio/mpeg',
        ),
      ]));

      final semantics = tester.getSemantics(
        find
            .ancestor(
              of: find.byIcon(Icons.broken_image),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.label, contains('audio/mpeg'));
    });
  });

  testWidgets('a user message without parts renders as plain text',
      (tester) async {
    await tester.pumpWidget(_wrap(
      TextMessageTile(
        roomId: 'r',
        message: TextMessage(
          id: 'plain-1',
          user: ChatUser.user,
          createdAt: DateTime(2026),
          text: 'just words',
        ),
      ),
    ));

    expect(find.text('just words'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.textSpan != null),
      isEmpty,
    );
  });
}
