import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';
import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

SourceReference _ref() => const SourceReference(
      documentId: 'd1',
      documentUri: 'file:///x/foo.pdf',
      content: 'body',
      chunkId: 'c1',
      documentTitle: 'Alpha',
      index: 1,
    );

Future<void> _pump(WidgetTester tester,
    {List<Override> overrides = const []}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: CitationsSection(sourceReferences: [_ref()])),
    ),
  ));
  await tester.tap(find.text('1 source')); // expand the section
  await tester.pump();
  await tester.tap(find.text('Alpha')); // expand the row
  await tester.pump();
}

void main() {
  testWidgets('no link with the default resolver', (tester) async {
    await _pump(tester);
    expect(find.byType(BrowserUrlLink), findsNothing);
  });

  testWidgets('renders a link when a resolver is injected', (tester) async {
    await _pump(tester, overrides: [
      documentBrowserUrlResolverProvider.overrideWithValue(
        (uri) => Uri.parse('https://example.test/foo.pdf/view'),
      ),
    ]);
    expect(find.byType(BrowserUrlLink), findsOneWidget);
  });
}
