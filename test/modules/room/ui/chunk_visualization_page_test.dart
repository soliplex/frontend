import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chunk_visualization_page.dart';
import 'package:soliplex_frontend/src/shared/browser_url_link.dart';
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

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );

// Maps any document uri to a distinguishable browser URL so tests can assert
// the link renders and which uri fed the resolver.
Uri _resolveEcho(String uri) => Uri.parse('https://docs.test/$uri');
final _resolverOverride = <Override>[
  documentBrowserUrlResolverProvider.overrideWithValue(_resolveEcho),
];

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

    await tester.pumpWidget(_wrap(
      ChunkVisualizationPage(
        api: api,
        roomId: 'room-1',
        chunkId: 'c1',
        useDialogLayout: true,
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

  testWidgets('document row shows the resolved link, not the raw uri',
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
        documentTitle: 'My Doc',
        documentUri: 'file://doc.pdf',
        pageNumbers: const [1],
      ),
      overrides: _resolverOverride,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsOneWidget);
    expect(find.text('document'), findsOneWidget);
    // Neither the raw path nor the chunk id appears in the detail block.
    expect(find.text('file://doc.pdf'), findsNothing);
    expect(find.text('chunk id'), findsNothing);
  });

  testWidgets('document link prefers the callers uri over the fetched one',
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
      overrides: _resolverOverride,
    ));
    await tester.pumpAndSettle();

    final link = tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink));
    expect(link.url.toString(), contains('caller'));
    expect(link.url.toString(), isNot(contains('fetched')));
  });

  testWidgets('document link falls back to the fetched uri when caller empty',
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
      overrides: _resolverOverride,
    ));
    await tester.pumpAndSettle();

    final link = tester.widget<BrowserUrlLink>(find.byType(BrowserUrlLink));
    expect(link.url.toString(), contains('fetched'));
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
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    // No documentTitle → the title shows the looked-up chunk id.
    expect(find.text('chunk-42'), findsOneWidget);
  });

  testWidgets('no document row when the uri does not resolve', (tester) async {
    // Default resolver returns null (standard build): no link, no raw path,
    // no chunk id in the detail block.
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
        documentTitle: 'My Doc',
        documentUri: 'file://doc.pdf',
        pageNumbers: const [1],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BrowserUrlLink), findsNothing);
    expect(find.text('document'), findsNothing);
    expect(find.text('chunk id'), findsNothing);
  });

  testWidgets('empty result shows the empty-state message and no detail block',
      (tester) async {
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
        documentTitle: 'My Doc',
        pageNumbers: const [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No page images available'), findsOneWidget);
    expect(find.text('chunk id'), findsNothing);
    expect(find.text('document'), findsNothing);
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
