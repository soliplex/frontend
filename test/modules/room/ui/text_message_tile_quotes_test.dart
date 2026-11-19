import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/quote_cards.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/quoted_context.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/room_pdf_scope.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/text_message_tile.dart';

import '../image_fixtures.dart';

const _quote = PdfQuote(
  text: 'Chunks shorter than 200 tokens lost the definitions.',
  documentTitle: 'field-notes.pdf',
  pageNumber: 4,
);

void main() {
  final opened = <PdfQuote>[];
  setUp(opened.clear);

  Future<void> pump(
    WidgetTester tester,
    TextMessage message, {
    bool withScope = true,
  }) {
    final tile =
        TextMessageTile(isStreaming: false, roomId: 'r', message: message);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(MessageExpansions()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: withScope
                ? RoomPdfScope(
                    open: (_) {},
                    openQuote: opened.add,
                    child: tile,
                  )
                : tile,
          ),
        ),
      ),
    );
  }

  TextMessage userMessage(String text, {List<MessagePart>? parts}) =>
      TextMessage(
        id: 'u1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: text,
        parts: parts,
      );

  testWidgets('a message read back as text shows its quotes as cards',
      (tester) async {
    await pump(
      tester,
      userMessage('${formatQuotedContext([_quote])}What did they change?'),
    );

    expect(find.byType(QuoteCard), findsOneWidget);
    expect(find.text('p. 4 · field-notes.pdf'), findsOneWidget);
    expect(find.text('What did they change?'), findsOneWidget);
    expect(find.textContaining('> —'), findsNothing,
        reason: 'the markdown is not shown raw');
  });

  testWidgets('quotes sent alone show no empty text', (tester) async {
    await pump(tester, userMessage(formatQuotedContext([_quote])));

    expect(find.byType(QuoteCard), findsOneWidget);
    expect(
        find.byType(Text).evaluate().where((e) {
          final text = (e.widget as Text).data;
          return text != null && text.trim().isEmpty;
        }),
        isEmpty);
  });

  testWidgets('a message with images reads quotes from its first text part',
      (tester) async {
    final quoted = formatQuotedContext([_quote]);
    await pump(
      tester,
      userMessage(
        '${quoted}Compare with this',
        parts: [
          TextPart('${quoted}Compare with this '),
          ImagePart(bytes: onePixelPng, mimeType: 'image/png', number: 1),
        ],
      ),
    );

    expect(find.byType(QuoteCard), findsOneWidget);
    expect(find.textContaining('Compare with this', findRichText: true),
        findsOneWidget);
  });

  testWidgets('tapping a card asks the room to reopen its PDF', (tester) async {
    await pump(tester, userMessage('${formatQuotedContext([_quote])}Why?'));

    await tester.tap(find.byType(QuoteCard));
    expect(opened, [_quote]);
  });

  testWidgets('outside a room the cards are not tappable', (tester) async {
    await pump(
      tester,
      userMessage('${formatQuotedContext([_quote])}Why?'),
      withScope: false,
    );

    final ink = tester.widget<InkWell>(
      find.descendant(
          of: find.byType(QuoteCard), matching: find.byType(InkWell)),
    );
    expect(ink.onTap, isNull);
  });

  testWidgets('a message without quotes is unchanged', (tester) async {
    await pump(tester, userMessage('> my own quote\n\nHello'));

    expect(find.byType(QuoteCard), findsNothing);
    expect(find.text('> my own quote\n\nHello'), findsOneWidget);
  });
}
