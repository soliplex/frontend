import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';

void main() {
  testWidgets('renders inline code with styled container', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FlutterMarkdownPlusRenderer(data: 'Use `myFunction()` here'),
        ),
      ),
    );

    expect(
      find.textContaining('myFunction()', findRichText: true),
      findsWidgets,
    );
  });
}
