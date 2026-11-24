import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/composer_draft.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';
import 'package:soliplex_frontend/src/modules/room/ui/inline_image_composer_controller.dart';

void main() {
  const quote = PdfQuote(
    text: 'Hybrid retrieval reduced unanswerable questions.',
    documentTitle: 'field-notes.pdf',
    pageNumber: 2,
  );

  late List<List<MessagePart>> sent;
  late List<PdfQuote> removed;
  late List<PdfQuote> tapped;

  setUp(() {
    sent = [];
    removed = [];
    tapped = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    List<PdfQuote> quotes = const [quote],
    InlineImageComposerController? controller,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ChatInput(
              controller: controller,
              onSend: sent.add,
              onCancel: () {},
              quotes: quotes,
              onQuoteRemoved: removed.add,
              onQuoteTap: tapped.add,
            ),
          ),
        ),
      );

  IconButton sendButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send));

  testWidgets('shows each waiting quote with its page and file',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(find.textContaining('Hybrid retrieval'), findsOneWidget);
    expect(find.text('p. 2 · field-notes.pdf'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Quote from field-notes.pdf, page 2')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a chip can be removed and reopens its PDF when tapped',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Remove quote'));
    expect(removed, [quote]);

    await tester.tap(find.textContaining('Hybrid retrieval'));
    expect(tapped, [quote]);
  });

  testWidgets('quotes alone can be sent, with nothing typed', (tester) async {
    await pump(tester);

    expect(sendButton(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    expect(sent.single, isEmpty, reason: 'the caller adds the quotes');
  });

  testWidgets('sends what was typed beside the quotes', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'Why?');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.send));
    expect((sent.single.single as TextPart).text, 'Why?');
  });

  testWidgets('with no quotes and nothing typed there is nothing to send',
      (tester) async {
    await pump(tester, quotes: const []);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('quotes do not override an image that could not be restored',
      (tester) async {
    final controller = InlineImageComposerController()
      ..restoreDraft('look at $composerDraftImageMarker');
    addTearDown(controller.dispose);
    await pump(tester, controller: controller);

    expect(sendButton(tester).onPressed, isNull);
  });
}
