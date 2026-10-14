import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/chunk_visualization_page.dart';
import 'package:soliplex_frontend/src/shared/failed_image.dart';

import '../../../helpers/fakes.dart';

// 1x1 red PNG pixel (minimal valid PNG).
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
  '2mP8/58BAwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
);
final _pngBase64 = base64Encode(_pngBytes);

class _ChunkVizApi extends FakeSoliplexApi {
  ChunkVisualization? nextVisualization;

  /// Answers a request that sends refs, when set; otherwise such a request
  /// gets [nextVisualization] like any other.
  ChunkVisualization? nextVisualizationWithRefs;
  Exception? nextVizError;

  int requestsWithRefs = 0;
  int requestsWithoutRefs = 0;

  @override
  Future<ChunkVisualization> getChunkVisualization(
    String roomId,
    String chunkId, {
    List<String>? refs,
    bool expand = false,
    String? database,
    CancelToken? cancelToken,
  }) async {
    final sendsRefs = refs != null && refs.isNotEmpty;
    if (sendsRefs) {
      requestsWithRefs++;
    } else {
      requestsWithoutRefs++;
    }
    if (nextVizError != null) throw nextVizError!;
    if (sendsRefs && nextVisualizationWithRefs != null) {
      return nextVisualizationWithRefs!;
    }
    if (nextVisualization != null) return nextVisualization!;
    throw StateError('Set nextVisualization or nextVizError before calling');
  }
}

ChunkVisualization _vizWithPages(int count) => ChunkVisualization(
      chunkId: 'c1',
      documentUri: 'doc.pdf',
      imagesBase64: List.filled(count, _pngBase64),
    );

/// The refs-not-sent answer has two pages and the refs-sent answer three, so
/// the dot count tells which one rendered.
_ChunkVizApi _apiAnsweringPerMode() => _ChunkVizApi()
  ..nextVisualization = _vizWithPages(2)
  ..nextVisualizationWithRefs = _vizWithPages(3);

Widget _citationPage(
  _ChunkVizApi api, {
  bool useDialogLayout = false,
  List<int> pageNumbers = const [],
  List<int> chunkPageNumbers = const [],
  List<String> chunkDocItemRefs = const [],
}) =>
    ChunkVisualizationPage(
      api: api,
      roomId: 'room-1',
      chunkId: 'c1',
      useDialogLayout: useDialogLayout,
      database: null,
      documentTitle: 'Cited Doc',
      pageNumbers: pageNumbers,
      chunkPageNumbers: chunkPageNumbers,
      docItemRefs: const ['#/texts/1', '#/texts/2'],
      chunkDocItemRefs: chunkDocItemRefs,
    );

const _noContextMessage = 'The answer used no context beyond this passage.';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  // Decoded page bytes are a shared imageCache key; clear it between tests so a
  // decode result from one test can't poison the next.
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('a citation opens without sending its refs', (tester) async {
    final api = _apiAnsweringPerMode();

    await tester.pumpWidget(_wrap(_citationPage(api)));
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsNWidgets(2));
  });

  testWidgets(
      "off labels the chunk's own pages, on labels the citation's pages",
      (tester) async {
    // Off draws only the chunk's items, on pages 4–5; on draws the whole
    // cited passage, on pages 3–5.
    await tester.pumpWidget(_wrap(_citationPage(
      _apiAnsweringPerMode(),
      pageNumbers: const [3, 4, 5],
      chunkPageNumbers: const [4, 5],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Page 4'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Page 3'), findsOneWidget);
  });

  testWidgets('off without the chunk pages labels by image position',
      (tester) async {
    await tester.pumpWidget(_wrap(_citationPage(
      _apiAnsweringPerMode(),
      pageNumbers: const [3, 4, 5],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Image 1 of 2'), findsOneWidget);
  });

  for (final (description, chunkRefs) in [
    ('the same refs as the chunk', ['#/texts/1', '#/texts/2']),
    // Budget clipping left the citation only part of the chunk.
    ('a subset of the chunk refs', ['#/texts/1', '#/texts/2', '#/texts/3']),
  ]) {
    testWidgets(
        'a citation quoting $description says so instead of offering the '
        'switch', (tester) async {
      await tester.pumpWidget(_wrap(_citationPage(
        _apiAnsweringPerMode(),
        chunkDocItemRefs: chunkRefs,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsNothing);
      expect(find.text('Show context the answer used'), findsNothing);
      expect(find.text(_noContextMessage), findsOneWidget);
      expect(find.byType(CircleAvatar), findsNWidgets(2));
    });
  }

  testWidgets('a citation quoting beyond the chunk offers the switch',
      (tester) async {
    await tester.pumpWidget(_wrap(_citationPage(
      _apiAnsweringPerMode(),
      chunkDocItemRefs: const ['#/texts/1'],
    )));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    expect(find.text(_noContextMessage), findsNothing);
  });

  testWidgets('a citation with refs offers the context switch', (tester) async {
    await tester.pumpWidget(_wrap(_citationPage(_apiAnsweringPerMode())));
    await tester.pumpAndSettle();

    expect(find.text('Show context the answer used'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('turning the context switch on shows the refs-sent result',
      (tester) async {
    await tester.pumpWidget(_wrap(_citationPage(_apiAnsweringPerMode())));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });

  testWidgets('switching back shows each earlier result without a new request',
      (tester) async {
    final api = _apiAnsweringPerMode();
    await tester.pumpWidget(_wrap(_citationPage(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(2));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    expect(api.requestsWithoutRefs, 1);
    expect(api.requestsWithRefs, 1);
  });

  testWidgets('retry re-fetches only the selected mode', (tester) async {
    final api = _apiAnsweringPerMode();
    await tester.pumpWidget(_wrap(_citationPage(api)));
    await tester.pumpAndSettle();

    api.nextVizError = Exception('boom');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load visualization'), findsOneWidget);

    api.nextVizError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(CircleAvatar), findsNWidgets(2));
    expect(api.requestsWithRefs, 2);
    expect(api.requestsWithoutRefs, 1);
  });

  testWidgets('switching mode returns the pager to the first page',
      (tester) async {
    await tester.pumpWidget(_wrap(_citationPage(_apiAnsweringPerMode())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Image 2 of 2'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Image 1 of 3'), findsOneWidget);
  });

  for (final useDialogLayout in [true, false]) {
    final layout = useDialogLayout ? 'dialog' : 'full-screen';
    testWidgets(
        '$layout layout: the switch sits under the title and its label '
        'toggles it', (tester) async {
      await tester.pumpWidget(_wrap(
        _citationPage(_apiAnsweringPerMode(), useDialogLayout: useDialogLayout),
      ));
      await tester.pumpAndSettle();

      final label = find.text('Show context the answer used');
      expect(label, findsOneWidget);
      expect(
        tester.getTopLeft(label).dy,
        greaterThan(tester.getBottomLeft(find.text('Cited Doc')).dy),
      );
      expect(
        tester.getBottomLeft(label).dy,
        lessThan(tester.getTopLeft(find.byType(PageView)).dy),
      );

      await tester.tap(label);
      await tester.pumpAndSettle();

      expect(find.byType(CircleAvatar), findsNWidgets(3));
    });
  }

  testWidgets('a page without refs offers no context switch', (tester) async {
    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: _apiAnsweringPerMode(),
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Cited Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Show context the answer used'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text(_noContextMessage), findsNothing);
  });

  testWidgets('shows loading indicator while fetching', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Test Doc',
        pageNumbers: const [1],
      ),
    ));

    // Before future completes, loading spinner is shown
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows images after successful load', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64, _pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'My Document',
        pageNumbers: const [3, 4],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('My Document'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);
    // Two page indicator dots
    expect(find.byType(CircleAvatar), findsNWidgets(2));
  });

  testWidgets(
      'a single corrupt base64 entry does not collapse the visualization',
      (tester) async {
    // Mixed valid/invalid payload. Without the per-image try/catch the
    // base64Decode FormatException propagates out of the .map() and fails
    // the entire future, taking down the whole visualization.
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64, '@@@not-base64@@@', _pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Test Doc',
        pageNumbers: const [1, 2, 3],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load visualization'), findsNothing);
    // All three page slots are still present (one is a placeholder).
    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });

  testWidgets('shows error with retry on failure', (tester) async {
    final api = _ChunkVizApi()
      ..nextVizError = Exception('network-leak-do-not-show');

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Test Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load visualization'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Raw exception text must not leak into the UI — re-adding the
    // dropped `Text(error.toString())` would expose internals.
    expect(find.textContaining('network-leak-do-not-show'), findsNothing);

    // Set success for retry
    api
      ..nextVizError = null
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load visualization'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('no page indicators for single image', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Doc',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('handles more pageNumbers than images', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Multi-page Chunk',
        pageNumbers: const [3, 4],
      ),
    ));
    await tester.pumpAndSettle();

    // Should show the image without crashing
    expect(find.byType(Image), findsOneWidget);
    // Should show a combined page label
    expect(find.text('Pages 3–4'), findsOneWidget);
  });

  testWidgets('dialog layout shows title bar with close button',
      (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: true,
        database: null,
        documentTitle: 'My Report',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('My Report'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets(
      'a corrupt base64 entry surfaces the decode reason in FailedImage label',
      (tester) async {
    // Behavioral coverage of the PageImageBroken arm of _buildPageImage: the
    // decoder produces a PageImageBroken with the FormatException message as
    // its reason, and the switch renders that reason inside FailedImage.
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: const ['@@@not-base64@@@'],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Test Doc',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FailedImage), findsOneWidget);
    expect(find.textContaining('Page image failed to decode:'), findsOneWidget);
  });

  testWidgets('tapping rotate button rotates the image', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Doc',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    // Initial rotation is 0
    final rotatedBox = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotatedBox.quarterTurns, 0);

    // Tap rotate button
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 1);
  });

  testWidgets('title falls back to the chunk id for a bare lookup',
      (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'chunk-42',
        documentUri: null,
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'chunk-42',
        useDialogLayout: false,
        database: null,
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    // No documentTitle → the title shows the looked-up chunk id.
    expect(find.text('chunk-42'), findsOneWidget);
  });

  testWidgets('empty result shows the empty-state message', (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: null,
        imagesBase64: const [],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        database: null,
        documentTitle: 'My Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No page images available'), findsOneWidget);
  });

  testWidgets('error state shows failure and retry, without the chunk id',
      (tester) async {
    final api = _ChunkVizApi()..nextVizError = Exception('boom');

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c-err',
        useDialogLayout: false,
        database: null,
        documentTitle: 'Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load visualization'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('c-err'), findsNothing);
  });
}
