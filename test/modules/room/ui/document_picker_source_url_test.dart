import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/ui/document_picker.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

Widget _picker(List<RagDocument> docs) => MaterialApp(
      home: Scaffold(
        body: DocumentPicker(
            documents: docs, selected: const {}, onChanged: (_) {}),
      ),
    );

void main() {
  testWidgets('subtitle is a browser link when source_url set', (tester) async {
    await tester.pumpWidget(_picker([
      const RagDocument(
        id: '1',
        title: 'Report.pdf',
        uri: 'file:///files/Report.pdf',
        metadata: {'source_url': 'https://example.test/Report.pdf/view'},
      ),
    ]));

    expect(find.byType(BrowserUrlLink), findsOneWidget);
    expect(find.text('file:///files/Report.pdf'), findsNothing);
  });

  testWidgets('no subtitle link or raw uri when source_url absent',
      (tester) async {
    await tester.pumpWidget(_picker([
      const RagDocument(id: '1', title: 'Report.pdf', uri: '/files/Report.pdf'),
    ]));

    expect(find.byType(BrowserUrlLink), findsNothing);
    // The internal path is not shown in the picker.
    expect(find.text('/files/Report.pdf'), findsNothing);
  });
}
