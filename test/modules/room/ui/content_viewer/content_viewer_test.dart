import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/content_viewer.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_body.dart';

Widget _inline(ContentViewer viewer) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: viewer)),
    );

void main() {
  testWidgets('plaintext shows no label', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'plaintext',
      content: 'just words',
      fill: false,
    )));

    expect(find.text('plaintext'), findsNothing);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    expect(
        find.textContaining('just words', findRichText: true), findsOneWidget);
  });

  testWidgets('python shows its label and Copy code', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'python',
      content: 'print(1)',
      fill: false,
    )));

    expect(find.text('python'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
  });

  testWidgets('svg routes to SvgBody', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'svg',
      content: '<svg xmlns="http://www.w3.org/2000/svg" width="10" '
          'height="10"><circle cx="5" cy="5" r="4"/></svg>',
      fill: false,
    )));

    expect(find.byType(SvgBody), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^SVG image\n')), findsOneWidget);
  });

  testWidgets('semantics label is Code block in python', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'python',
      content: 'print(1)',
      fill: false,
    )));

    // The header's label text merges into the block's label after it.
    expect(find.bySemanticsLabel(RegExp(r'^Code block in python\n')),
        findsOneWidget);
  });

  testWidgets('semantics label is Code block for plaintext', (tester) async {
    await tester.pumpWidget(_inline(const ContentViewer(
      language: 'plaintext',
      content: 'just words',
      fill: false,
    )));

    expect(find.bySemanticsLabel(RegExp(r'^Code block$')), findsOneWidget);
  });
}
