import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';

/// Builds a reference labelled by its filename, with a distinct
/// [SourceReference.documentTitle] the collapsed row is expected not to show —
/// the title surfaces only in the expanded area.
///
/// The URI ends in [fileName], so the name drives both the label and the PDF
/// affordance. Callers usually vary the name; pass [uri] outright to address a
/// file embedded in another document.
SourceReference _ref({
  required int index,
  String? fileName,
  String? uri,
  Object? documentTitle = _unset,
  List<String> headings = const [],
  String content = 'Test content',
  List<int> pageNumbers = const [],
  String? database,
}) {
  final name = fileName ?? 'doc-$index.txt';
  return SourceReference(
    documentId: 'doc-$index',
    documentUri: uri ?? 'file:///docs/$name',
    content: content,
    chunkId: 'chunk-$index',
    documentTitle: identical(documentTitle, _unset)
        ? 'Document $index'
        : documentTitle as String?,
    headings: headings,
    pageNumbers: pageNumbers,
    index: index,
    database: database,
  );
}

/// Sentinel distinguishing "caller passed null" from "caller passed nothing",
/// so a test can ask for a reference with no title at all.
const Object _unset = Object();

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('groupCitationsByDatabase', () {
    test('a list naming no database is one unnamed group', () {
      final groups = groupCitationsByDatabase([_ref(index: 1), _ref(index: 2)]);
      expect(groups, hasLength(1));
      expect(groups.single.database, isNull);
      expect(groups.single.entries.map((e) => e.index), [0, 1]);
    });

    test('groups in first-seen order, the unnamed last, indices kept', () {
      final groups = groupCitationsByDatabase([
        _ref(index: 1, database: 'wiki'),
        _ref(index: 2),
        _ref(index: 3, database: 'papers'),
        _ref(index: 4, database: 'wiki'),
        _ref(index: 5, database: ''),
      ]);
      expect(groups.map((g) => g.database), ['wiki', 'papers', null]);
      expect(groups[0].entries.map((e) => e.index), [0, 3]);
      expect(groups[1].entries.map((e) => e.index), [2]);
      expect(groups[2].entries.map((e) => e.index), [1, 4]);
    });
  });

  testWidgets('citations from several databases are grouped under their names',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'a.txt', database: 'wiki'),
          _ref(index: 2, fileName: 'b.txt'),
          _ref(index: 3, fileName: 'c.txt', database: 'papers'),
        ],
      ),
    ));

    expect(find.text('wiki'), findsOneWidget);
    expect(find.text('papers'), findsOneWidget);
    expect(find.text('Other sources'), findsOneWidget);
    // Headings come in first-seen order, the unnamed group last, and the
    // rows keep their answer numbering.
    final wiki = tester.getTopLeft(find.text('wiki')).dy;
    final papers = tester.getTopLeft(find.text('papers')).dy;
    final other = tester.getTopLeft(find.text('Other sources')).dy;
    final a = tester.getTopLeft(find.text('a.txt')).dy;
    final b = tester.getTopLeft(find.text('b.txt')).dy;
    final c = tester.getTopLeft(find.text('c.txt')).dy;
    expect(
        wiki < a && a < papers && papers < c && c < other && other < b, isTrue);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('an empty list renders the header and no rows', (tester) async {
    await tester.pumpWidget(_wrap(
      const CitationsSection(sourceReferences: []),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('0 sources'), findsOneWidget);
    expect(find.text('Other sources'), findsNothing);
  });

  testWidgets('a single named database still shows its name', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [_ref(index: 1, database: 'papers')],
      ),
    ));

    expect(find.text('papers'), findsOneWidget);
    expect(find.text('Other sources'), findsNothing);
  });

  testWidgets('citations naming no database render without headings',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(sourceReferences: [_ref(index: 1), _ref(index: 2)]),
    ));

    expect(find.text('Other sources'), findsNothing);
    expect(find.byIcon(Icons.storage_outlined), findsNothing);
  });

  testWidgets('expanding a row in a group keys on the citation, not its place',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'a.txt', content: 'Alpha text'),
          _ref(
              index: 2,
              fileName: 'b.txt',
              database: 'wiki',
              content: 'Bravo text'),
        ],
      ),
    ));

    // 'b.txt' is first on screen (its group leads) but second in the list.
    await tester.tap(find.text('b.txt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bravo text'), findsOneWidget);
    expect(find.textContaining('Alpha text'), findsNothing);
  });

  test('the clipboard text names the database', () {
    final text = formatCitationForClipboard(_ref(index: 1, database: 'wiki'));
    expect(text, contains('database: wiki'));
    expect(formatCitationForClipboard(_ref(index: 1)),
        isNot(contains('database:')));
  });

  testWidgets(
      'expanded citation content renders non-selectable inside a SelectionArea',
      (tester) async {
    // A self-selecting (selectable:true) markdown nested in a SelectionArea
    // captures the drag gesture itself and drops out of the transcript-wide
    // selection; this proves the citation content renders selectable:false and
    // so joins the surrounding area's selection.
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: SingleChildScrollView(
              child: CitationsSection(
                sourceReferences: [
                  _ref(index: 1, fileName: 'Alpha.txt', content: 'cited body'),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    // The section is expanded by default (issue #463), so the source title is
    // visible without a tap; tapping it opens the row to render the content.
    await tester.tap(find.text('Alpha.txt'));
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

  testWidgets('sources are expanded and visible by default (issue #463)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'Alpha.txt'),
          _ref(index: 2, fileName: 'Beta.txt'),
        ],
      ),
    ));

    // No tap needed — each source's filename shows immediately, and the
    // document title is not what labels the row.
    expect(find.text('Alpha.txt'), findsOneWidget);
    expect(find.text('Beta.txt'), findsOneWidget);
    expect(find.text('Document 1'), findsNothing);
  });

  testWidgets('tapping the header collapses then re-expands the section',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
          sourceReferences: [_ref(index: 1, fileName: 'Alpha.txt')]),
    ));

    // Starts expanded (issue #463); the header still toggles it closed...
    expect(find.text('Alpha.txt'), findsOneWidget);

    await tester.tap(find.text('1 source'));
    await tester.pump();
    expect(find.text('Alpha.txt'), findsNothing);

    // ...and back open.
    await tester.tap(find.text('1 source'));
    await tester.pump();
    expect(find.text('Alpha.txt'), findsOneWidget);
  });

  testWidgets('displays badge number from SourceReference.index',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
          sourceReferences: [_ref(index: 4, fileName: 'Fourth.txt')]),
    ));

    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('tapping a row expands to show headings and content',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            fileName: 'Doc.txt',
            headings: ['Chapter 1', 'Section 2'],
            content: 'Preview text here',
          ),
        ],
      ),
    ));

    // Section expanded by default (issue #463); the row's heading breadcrumb
    // stays hidden until the row itself is tapped open.
    expect(find.text('Chapter 1 > Section 2'), findsNothing);

    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    expect(find.text('Chapter 1 > Section 2'), findsOneWidget);
    expect(find.text('Preview text here'), findsOneWidget);
  });

  testWidgets(
      'transcript stays collapsed and non-scrolling until asked to expand',
      (tester) async {
    // Issue #451: an expanded citation must not trap the thread's scroll. The
    // transcript preview is non-scrolling by default; only an explicit expand
    // turns it into an internally-scrollable band.
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'Doc.txt', content: 'Cited passage body'),
        ],
      ),
    ));

    // Expanded by default (issue #463); open the single source's row.
    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    SingleChildScrollView transcriptScroller() => tester.widget(
          find.ancestor(
            of: find.byType(FlutterMarkdownPlusRenderer),
            matching: find.byType(SingleChildScrollView),
          ),
        );

    // Collapsed: the invite shows and the preview can't consume scroll, so the
    // thread scrolls straight past it.
    expect(find.text('Show full transcript'), findsOneWidget);
    expect(find.text('Show less'), findsNothing);
    expect(
      transcriptScroller().physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    // Expanded: the reader opts into the inner scroll for this one passage.
    await tester.tap(find.text('Show full transcript'));
    await tester.pump();

    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Show full transcript'), findsNothing);
    expect(
      transcriptScroller().physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );
  });

  testWidgets('expanded row shows the chunk id', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [_ref(index: 1, fileName: 'Doc.txt')],
      ),
    ));

    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    expect(find.textContaining('chunk-1'), findsOneWidget);
  });

  testWidgets('shows page numbers when present', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, pageNumbers: [5, 6])
        ],
      ),
    ));

    expect(find.text('p.5-6'), findsOneWidget);
  });

  testWidgets('an attachment citation names the document it is embedded in',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
          ),
        ],
      ),
    ));

    // The cited file keeps the primary slot — never the container — and states
    // its provenance underneath.
    expect(find.text('budget.xlsx'), findsOneWidget);
    expect(find.text('in annual-report.pdf'), findsOneWidget);

    // The provenance sits inside the row's tap target, so opening a citation
    // by its container line works like opening it by its name.
    await tester.tap(find.text('in annual-report.pdf'));
    await tester.pump();

    expect(find.textContaining('chunk-1'), findsOneWidget);
  });

  testWidgets('a nested attachment chains the documents containing it',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            uri: 'file:///docs/a.pdf#attachment=b.pdf#attachment=inner.xlsx',
          ),
        ],
      ),
    ));

    expect(find.text('inner.xlsx'), findsOneWidget);
    expect(find.text('in a.pdf > b.pdf'), findsOneWidget);
  });

  testWidgets('the label tooltip carries both names in full', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
          ),
        ],
      ),
    ));

    // Both lines ellipsize, so a tooltip naming only the container would leave
    // the cited file — the thing the citation is about — unreadable.
    expect(
      find.byTooltip('budget.xlsx embedded in annual-report.pdf'),
      findsOneWidget,
    );
  });

  testWidgets('the label tooltip of a plain document carries its name',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [_ref(index: 1, fileName: 'standalone.pdf')],
      ),
    ));

    expect(find.byTooltip('standalone.pdf'), findsOneWidget);
  });

  testWidgets('a citation of a plain document shows no provenance line',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [_ref(index: 1, fileName: 'standalone.pdf')],
      ),
    ));

    expect(find.text('standalone.pdf'), findsOneWidget);
    expect(find.textContaining(RegExp('^in ')), findsNothing);
  });

  testWidgets('an expanded citation shows the document title', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            fileName: 'Doc.txt',
            documentTitle: 'Annual Operations Review',
          ),
        ],
      ),
    ));

    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    expect(find.textContaining('Annual Operations Review'), findsOneWidget);
  });

  testWidgets('an expanded citation whose label is the title shows it once',
      (tester) async {
    // The row label falls back to the title when the uri names no file.
    // Repeating it under a `title` lead-in would print the same string twice.
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(
            index: 1,
            uri: 'file:///docs/',
            documentTitle: 'Annual Operations Review',
          ),
        ],
      ),
    ));

    await tester.tap(find.text('Annual Operations Review'));
    await tester.pump();

    expect(find.textContaining('Annual Operations Review'), findsOneWidget);
  });

  testWidgets('an expanded citation with no title shows no title row',
      (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'Doc.txt', documentTitle: null),
        ],
      ),
    ));

    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    // The label goes with the value — a lone `title` lead-in announces nothing.
    expect(find.textContaining('chunk-1'), findsOneWidget);
    expect(find.textContaining('title  '), findsNothing);
  });

  testWidgets('a blank document title is treated as absent', (tester) async {
    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'Doc.txt', documentTitle: '   '),
        ],
      ),
    ));

    await tester.tap(find.text('Doc.txt'));
    await tester.pump();

    expect(find.textContaining('chunk-1'), findsOneWidget);
    expect(find.textContaining('title  '), findsNothing);
  });

  testWidgets('shows PDF preview affordance only for PDF sources',
      (tester) async {
    SourceReference? tappedRef;

    await tester.pumpWidget(_wrap(
      CitationsSection(
        sourceReferences: [
          _ref(index: 1, fileName: 'Text File.txt'),
          _ref(index: 2, fileName: 'PDF File.pdf'),
        ],
        onShowChunkVisualization: (ref) => tappedRef = ref,
      ),
    ));

    // Section is expanded by default (issue #463), so both rows are visible.
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
        fileName: 'Doc.txt',
        headings: ['Chapter 1', 'Section 2'],
        pageNumbers: [5, 6],
        content: 'Preview text here',
      );

      expect(
        formatCitationForClipboard(ref),
        'Doc.txt\n'
        'Chapter 1 > Section 2\n'
        'p.5-6\n'
        'file:///docs/Doc.txt\n'
        'chunk id: chunk-1\n'
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

      expect(formatCitationForClipboard(ref), 'Doc\nchunk id: chunk-1');
    });
  });

  group('formatAllCitationsForClipboard', () {
    test('formats a single ref without trailing separator', () {
      expect(
        formatAllCitationsForClipboard([
          _ref(index: 1, fileName: 'Alpha.txt', content: 'first'),
        ]),
        formatCitationForClipboard(
          _ref(index: 1, fileName: 'Alpha.txt', content: 'first'),
        ),
      );
    });

    test('joins multiple refs with a blank-line/rule/blank-line separator', () {
      final alpha = _ref(index: 1, fileName: 'Alpha.txt', content: 'first');
      final beta = _ref(index: 2, fileName: 'Beta.txt', content: 'second');

      expect(
        formatAllCitationsForClipboard([alpha, beta]),
        '${formatCitationForClipboard(alpha)}'
        '\n\n---\n\n'
        '${formatCitationForClipboard(beta)}',
      );
    });
  });
}
