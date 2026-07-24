import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/document_source.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders a browser link when a url is given', (tester) async {
    final url = Uri.parse('https://viewer.test/view');
    await tester.pumpWidget(
      _host(DocumentSource(url: url, documentUri: 'file:///x/a.pdf')),
    );
    expect(tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink)).url, url);
    expect(find.text('file:///x/a.pdf'), findsNothing);
  });

  testWidgets('shows the document uri as text when there is no url',
      (tester) async {
    await tester.pumpWidget(
      _host(const DocumentSource(url: null, documentUri: 'file:///x/a.pdf')),
    );
    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.text('file:///x/a.pdf'), findsOneWidget);
  });

  testWidgets('renders nothing when there is no url and no document uri',
      (tester) async {
    await tester.pumpWidget(
      _host(const DocumentSource(url: null, documentUri: '')),
    );
    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
