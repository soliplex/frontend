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

void main() {
  testWidgets('shows a browser link and keeps the raw uri when source_url set',
      (tester) async {
    await tester.pumpWidget(_card([
      const RagDocument(
        id: 'd1',
        title: 'Doc',
        uri: 'file:///x/foo.pdf',
        metadata: {'source_url': 'https://example.test/foo.pdf/view'},
      ),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('foo.pdf')); // display name expands the tile
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsOneWidget);
    expect(find.text('file:///x/foo.pdf'), findsOneWidget); // raw uri retained
  });

  testWidgets('shows no link when source_url absent', (tester) async {
    await tester.pumpWidget(_card([
      const RagDocument(id: 'd1', title: 'Doc', uri: 'file:///x/foo.pdf'),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('foo.pdf'));
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.text('file:///x/foo.pdf'), findsOneWidget);
  });
}
