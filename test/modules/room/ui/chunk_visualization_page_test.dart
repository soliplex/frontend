import 'dart:convert';

import 'package:flutter/material.dart';
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
  Exception? nextVizError;

  @override
  Future<ChunkVisualization> getChunkVisualization(
    String roomId,
    String chunkId, {
    List<String>? refs,
    bool expand = true,
    CancelToken? cancelToken,
  }) async {
    if (nextVizError != null) throw nextVizError!;
    if (nextVisualization != null) return nextVisualization!;
    throw StateError('Set nextVisualization or nextVizError before calling');
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // Decoded page bytes are a shared imageCache key; clear it between tests so a
  // decode result from one test can't poison the next.
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChunkVisualizationPage(
          api: api,
          roomId: 'room-1',
          chunkId: 'c1',
          useDialogLayout: true,
          documentTitle: 'My Report',
          pageNumbers: const [1],
        ),
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

  testWidgets('detail block prefers the callers uri over the fetched one',
      (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'file://fetched.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        documentTitle: 'My Doc',
        documentUri: 'file://caller.pdf',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('c1'), findsOneWidget);
    // Name is the title (once); the detail block shows the caller's uri, not
    // the fetched one.
    expect(find.text('My Doc'), findsOneWidget);
    expect(find.text('file://caller.pdf'), findsOneWidget);
    expect(find.text('file://fetched.pdf'), findsNothing);
  });

  testWidgets('detail block treats an empty caller uri as absent',
      (tester) async {
    // A citation whose documentUri is '' must not shadow a real fetched uri.
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'file://fetched.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        documentUri: '',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('file://fetched.pdf'), findsOneWidget);
  });

  testWidgets('empty result still shows the chunk id in the detail block',
      (tester) async {
    // The lookup flow can produce zero images; the detail block (chunk id)
    // must still render alongside the empty-state message.
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
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No page images available'), findsOneWidget);
    expect(find.text('chunk id'), findsOneWidget);
    expect(find.text('c1'), findsOneWidget);
  });

  testWidgets('detail block falls back to the fetched uri when caller has none',
      (tester) async {
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: 'file://doc.pdf',
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('c1'), findsOneWidget);
    expect(find.text('file://doc.pdf'), findsOneWidget);
    expect(find.text('Chunk preview'), findsOneWidget);
  });

  testWidgets('detail block hides the document row when no uri is available',
      (tester) async {
    // Bare lookup + backend returns a null document_uri: only the chunk id
    // shows, no empty "document" label.
    final api = _ChunkVizApi()
      ..nextVisualization = ChunkVisualization(
        chunkId: 'c1',
        documentUri: null,
        imagesBase64: [_pngBase64],
      );

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: false,
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('chunk id'), findsOneWidget);
    expect(find.text('c1'), findsOneWidget);
    expect(find.text('document'), findsNothing);
  });

  testWidgets('detail block shows the chunk id in the error state',
      (tester) async {
    final api = _ChunkVizApi()..nextVizError = Exception('boom');

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c-err',
        useDialogLayout: false,
        documentTitle: 'Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Failed to load visualization'), findsOneWidget);
    expect(find.text('c-err'), findsOneWidget);
  });
}
