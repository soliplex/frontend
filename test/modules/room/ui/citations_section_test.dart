import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/shared/failed_image.dart';

SourceReference _ref({
  required int index,
  String? title,
  bool pdf = false,
  List<String> headings = const [],
  String content = 'Test content',
  List<int> pageNumbers = const [],
  List<String> pictureRefs = const [],
}) =>
    SourceReference(
      documentId: 'doc-$index',
      documentUri: pdf ? 's3://bucket/doc-$index.pdf' : 'file://doc-$index.txt',
      content: content,
      chunkId: 'chunk-$index',
      documentTitle: title ?? 'Document $index',
      headings: headings,
      pageNumbers: pageNumbers,
      pictureRefs: pictureRefs,
      index: index,
    );

// 1x1 red PNG pixel (minimal valid PNG).
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
  '2mP8/58BAwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
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

  group('cited figures', () {
    // Note: assertions target the fetch wiring + the thumbnail's loading slot
    // (a CircularProgressIndicator), not the decoded image — image decoding
    // does not run in widget tests without runAsync, so the painted bytes are
    // framework territory, not our logic.
    testWidgets('fetches a figure per pictureRef when a fetcher is provided',
        (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(_wrap(
        CitationsSection(
          sourceReferences: [
            _ref(index: 1, title: 'Alpha', pictureRefs: ['#/pictures/0']),
          ],
          onFetchPicture: (ref, pictureRef) async {
            calls.add((ref.documentId, pictureRef));
            return _pngBytes;
          },
        ),
      ));

      // Expand the section, then the citation row, to reveal figures.
      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump();

      // The fetcher ran with the citation's document id + picture ref, and the
      // thumbnail rendered its loading slot while the fetch is in flight.
      expect(calls, [('doc-1', '#/pictures/0')]);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a fallback when a figure fetch fails', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CitationsSection(
                sourceReferences: [
                  _ref(index: 1, title: 'Alpha', pictureRefs: ['#/pictures/0']),
                ],
                onFetchPicture: (ref, pictureRef) async =>
                    throw Exception('fetch failed'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump(); // build thumbnail, start fetch
      await tester.pump(); // resolve the failing future

      // The failed fetch surfaces the broken-image fallback, and the
      // rethrown error is handled by the FutureBuilder (not an uncaught throw).
      expect(find.byType(FailedImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NotFoundException shows "not found" with no retry',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CitationsSection(
                sourceReferences: [
                  _ref(index: 1, title: 'Alpha', pictureRefs: ['#/pictures/0']),
                ],
                onFetchPicture: (ref, pictureRef) async {
                  calls++;
                  throw const NotFoundException(message: 'missing');
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump(); // build thumbnail, start fetch
      await tester.pump(); // resolve the failing future

      // A missing figure is permanent — distinct label, no retry affordance.
      expect(find.text('Figure not found'), findsOneWidget);
      expect(find.byTooltip('Tap to retry'), findsNothing);

      // Tapping the fallback does not re-fetch.
      await tester.tap(find.byType(FailedImage));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('a transient failure offers retry and re-fetches on tap',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CitationsSection(
                sourceReferences: [
                  _ref(index: 1, title: 'Alpha', pictureRefs: ['#/pictures/0']),
                ],
                onFetchPicture: (ref, pictureRef) async {
                  calls++;
                  if (calls == 1) throw Exception('transient');
                  return _pngBytes;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump(); // build thumbnail, start fetch
      await tester.pump(); // resolve the failing future

      expect(find.text('Figure unavailable'), findsOneWidget);
      expect(calls, 1);

      // Tapping retry re-runs the fetch (back to the loading slot).
      await tester.tap(find.byTooltip('Tap to retry'));
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not fetch when pictureRefs is empty', (tester) async {
      var fetchCount = 0;
      await tester.pumpWidget(_wrap(
        CitationsSection(
          sourceReferences: [_ref(index: 1, title: 'Alpha')],
          onFetchPicture: (ref, pictureRef) async {
            fetchCount++;
            return _pngBytes;
          },
        ),
      ));

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump();

      expect(fetchCount, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('renders no figures when no fetcher is provided',
        (tester) async {
      await tester.pumpWidget(_wrap(
        CitationsSection(
          sourceReferences: [
            _ref(index: 1, title: 'Alpha', pictureRefs: ['#/pictures/0']),
          ],
        ),
      ));

      await tester.tap(find.text('1 source'));
      await tester.pump();
      await tester.tap(find.text('Alpha'));
      await tester.pump();

      // No fetcher → the figures strip is not built (no loading slot).
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
