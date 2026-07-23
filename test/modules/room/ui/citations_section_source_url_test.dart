import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

SourceReference _ref({Uri? sourceUrl}) => SourceReference(
      documentId: 'd1',
      documentUri: 'file:///x/foo.pdf',
      content: 'body',
      chunkId: 'c1',
      documentTitle: 'Alpha',
      sourceUrl: sourceUrl,
      index: 1,
    );

Future<void> _pump(WidgetTester tester, SourceReference ref) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: CitationsSection(sourceReferences: [ref])),
    ),
  ));
  await tester.tap(find.text('1 source')); // expand the section
  await tester.pump();
  await tester.tap(find.text('Alpha')); // expand the row
  await tester.pump();
}

void main() {
  testWidgets('no link and no raw path when the citation carries no source_url',
      (tester) async {
    await _pump(tester, _ref());
    expect(find.byType(BrowserUrlLink), findsNothing);
    // The internal file path is never shown.
    expect(
      find.textContaining('file:///x/foo.pdf', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('renders the link when the citation carries a source_url',
      (tester) async {
    final url = Uri.parse('https://example.test/foo.pdf/view');
    await _pump(tester, _ref(sourceUrl: url));
    final link = tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink));
    expect(link.url, url);
  });
}
