import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';

Widget _inArea(Widget child) =>
    MaterialApp(home: Scaffold(body: SelectionArea(child: child)));

void main() {
  testWidgets('selectable:false markdown renders inside a SelectionArea',
      (tester) async {
    await tester.pumpWidget(_inArea(
      const FlutterMarkdownPlusRenderer(
        data: '# Hi\n\nbody text',
        selectable: false,
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMarkdownPlusRenderer), findsOneWidget);
  });
}
