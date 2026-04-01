import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';

SourceReference _ref({
  required int index,
  String? title,
  bool pdf = false,
  List<String> headings = const [],
  String content = 'Test content',
  List<int> pageNumbers = const [],
}) =>
    SourceReference(
      documentId: 'doc-$index',
      documentUri: pdf ? 's3://bucket/doc-$index.pdf' : 'file://doc-$index.txt',
      content: content,
      chunkId: 'chunk-$index',
      documentTitle: title ?? 'Document $index',
      headings: headings,
      pageNumbers: pageNumbers,
      index: index,
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('header shows source count', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(sourceReferences: [_ref(index: 1), _ref(index: 2)]),
    ));

    expect(find.text('2 sources'), findsOneWidget);
  });

  testWidgets('header shows singular for one source', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(sourceReferences: [_ref(index: 1)]),
    ));

    expect(find.text('1 source'), findsOneWidget);
  });

  testWidgets('tapping header expands to show source titles', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, title: 'Alpha'),
          _ref(index: 2, title: 'Beta'),
        ],
      ),
    ));

    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.text('2 sources'));
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('tapping header again collapses section', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(sourceReferences: [_ref(index: 1, title: 'Alpha')]),
    ));

    await tester.tap(find.text('1 source'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.text('1 source'));
    await tester.pump();
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('displays badge number from SourceReference.index',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(sourceReferences: [_ref(index: 4, title: 'Fourth')]),
    ));

    await tester.tap(find.text('1 source'));
    await tester.pump();

    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('tapping a row expands to show headings and content',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            title: 'Doc',
            headings: ['Chapter 1', 'Section 2'],
            content: 'Preview text here',
          ),
        ],
      ),
    ));

    await tester.tap(find.text('1 source'));
    await tester.pump();

    expect(find.text('Chapter 1 > Section 2'), findsNothing);

    await tester.tap(find.text('Doc'));
    await tester.pump();

    expect(find.text('Chapter 1 > Section 2'), findsOneWidget);
    expect(find.text('Preview text here'), findsOneWidget);
  });

  testWidgets('shows page numbers when present', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, pageNumbers: [5, 6])
        ],
      ),
    ));

    await tester.tap(find.text('1 source'));
    await tester.pump();

    expect(find.text('p.5-6'), findsOneWidget);
  });

  testWidgets('shows PDF button only for PDF sources', (tester) async {
    SourceReference? tappedRef;

    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, title: 'Text File', pdf: false),
          _ref(index: 2, title: 'PDF File', pdf: true),
        ],
        onShowChunkVisualization: (ref) => tappedRef = ref,
      ),
    ));

    // Expand section
    await tester.tap(find.text('2 sources'));
    await tester.pump();

    // Expand both rows
    await tester.tap(find.text('Text File'));
    await tester.pump();
    await tester.tap(find.text('PDF File'));
    await tester.pump();

    // Only one "View in PDF" button (for the PDF source)
    expect(find.text('View in PDF'), findsOneWidget);

    await tester.tap(find.text('View in PDF'));
    await tester.pump();

    expect(tappedRef?.documentId, 'doc-2');
  });
}
