import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';

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
  testWidgets(
      'expanded citation content renders non-selectable inside a SelectionArea',
      (tester) async {
    // A self-selecting (selectable:true) markdown nested in a SelectionArea
    // captures the drag gesture itself and drops out of the transcript-wide
    // selection; this proves the citation content renders selectable:false and
    // so joins the surrounding area's selection.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          child: SingleChildScrollView(
            child: CitationsSection(
              sourceReferences: [
                _ref(index: 1, title: 'Alpha', content: 'cited body'),
              ],
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('Alpha'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final md = tester.widget<FlutterMarkdownPlusRenderer>(
      find.byType(FlutterMarkdownPlusRenderer),
    );
    expect(md.selectable, isFalse);
  });

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

  testWidgets('shows PDF preview affordance only for PDF sources',
      (tester) async {
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

    // Only the PDF source exposes the eye affordance, and it sits in
    // the source's header row (no need to expand the row to reveal it).
    expect(find.byTooltip('View source PDF'), findsOneWidget);

    await tester.tap(find.byTooltip('View source PDF'));
    await tester.pump();

    expect(tappedRef?.documentId, 'doc-2');
  });

  group('formatCitationForClipboard', () {
    test('emits title, headings, pages, uri, and content in order', () {
      final ref = _ref(
        index: 1,
        title: 'Doc',
        headings: ['Chapter 1', 'Section 2'],
        pageNumbers: [5, 6],
        content: 'Preview text here',
      );

      expect(
        formatCitationForClipboard(ref),
        'Doc\n'
        'Chapter 1 > Section 2\n'
        'p.5-6\n'
        'file://doc-1.txt\n'
        '\n'
        'Preview text here',
      );
    });

    test('omits headings, pages, uri, and content when absent', () {
      final ref = SourceReference(
        documentId: 'doc-1',
        documentUri: '',
        content: '',
        chunkId: 'chunk-1',
        documentTitle: 'Doc',
        headings: const [],
        pageNumbers: const [],
        index: 1,
      );

      expect(formatCitationForClipboard(ref), 'Doc');
    });
  });

  group('formatAllCitationsForClipboard', () {
    test('formats a single ref without trailing separator', () {
      expect(
        formatAllCitationsForClipboard([
          _ref(index: 1, title: 'Alpha', content: 'first'),
        ]),
        formatCitationForClipboard(
          _ref(index: 1, title: 'Alpha', content: 'first'),
        ),
      );
    });

    test('joins multiple refs with a blank-line/rule/blank-line separator', () {
      final alpha = _ref(index: 1, title: 'Alpha', content: 'first');
      final beta = _ref(index: 2, title: 'Beta', content: 'second');

      expect(
        formatAllCitationsForClipboard([alpha, beta]),
        '${formatCitationForClipboard(alpha)}'
        '\n\n---\n\n'
        '${formatCitationForClipboard(beta)}',
      );
    });
  });
}
