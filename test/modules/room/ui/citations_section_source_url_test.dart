import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';
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

Future<void> _pump(
  WidgetTester tester,
  SourceReference ref, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
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
  testWidgets('renders the link from the citation source_url', (tester) async {
    final url = Uri.parse('https://example.test/foo.pdf/view');
    await _pump(tester, _ref(sourceUrl: url));
    expect(tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink)).url, url);
  });

  testWidgets('a resolver derives the link when source_url is absent',
      (tester) async {
    final resolved = Uri.parse('https://viewer.test/foo.pdf/view');
    await _pump(
      tester,
      _ref(),
      overrides: [
        documentBrowserUrlResolverProvider.overrideWithValue((_) => resolved),
      ],
    );
    expect(
      tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink)).url,
      resolved,
    );
  });

  testWidgets('shows the document uri as text with no source_url or resolver',
      (tester) async {
    await _pump(tester, _ref());
    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.text('file:///x/foo.pdf'), findsOneWidget);
  });
}
