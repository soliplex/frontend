import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/ui/room_info/documents_card.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

Widget _card(List<RagDocument> docs) => MaterialApp(
      home: Scaffold(
        body: DocumentsCard(
          documentsFuture: Future.value(docs),
          onRetry: () {},
        ),
      ),
    );

const _doc = RagDocument(
  id: 'd1',
  title: 'RAW-TITLE',
  uri: 'file:///x/foo.pdf',
  metadata: {'source_url': 'https://example.test/foo.pdf/view'},
);

void main() {
  testWidgets('expanded detail shows the browser link, not the raw uri',
      (tester) async {
    await tester.pumpWidget(_card([_doc]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('foo.pdf')); // display name expands the tile
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsOneWidget);
    // Internal file path is not shown in the expanded detail.
    expect(find.text('file:///x/foo.pdf'), findsNothing);
  });

  testWidgets('detail shows the document uri when source_url absent',
      (tester) async {
    await tester.pumpWidget(_card([
      const RagDocument(id: 'd1', title: 'Doc', uri: 'file:///x/foo.pdf'),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('foo.pdf'));
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.text('file:///x/foo.pdf'), findsOneWidget);
  });

  testWidgets('metadata dialog carries the file uri and a friendly title',
      (tester) async {
    await tester.pumpWidget(_card([_doc]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('foo.pdf'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show metadata'));
    await tester.pumpAndSettle();

    // The internal path lives in the metadata dialog.
    expect(find.text('file:///x/foo.pdf'), findsOneWidget);
    expect(find.text('uri'), findsOneWidget);
    // Dialog is titled with the display name, not the raw doc.title.
    expect(find.text('RAW-TITLE'), findsNothing);
  });
}
