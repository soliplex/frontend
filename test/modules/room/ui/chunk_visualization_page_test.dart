import 'dart:convert';
import 'dart:typed_data' show Uint8List;

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
    CancelToken? cancelToken,
  }) async {
    if (nextVizError != null) throw nextVizError!;
    if (nextVisualization != null) return nextVisualization!;
    throw StateError('Set nextVisualization or nextVizError before calling');
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
    final api = _ChunkVizApi()..nextVizError = Exception('Network error');

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

  group('readPngDimensions', () {
    test('reads width and height from valid PNG', () {
      final (w, h) = readPngDimensions(_pngBytes);
      expect(w, 1);
      expect(h, 1);
    });

    test('returns (0, 0) for non-PNG bytes', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      final (w, h) = readPngDimensions(bytes);
      expect(w, 0);
      expect(h, 0);
    });

    test('returns (0, 0) for truncated data', () {
      final (w, h) = readPngDimensions(Uint8List.fromList([0x89, 0x50]));
      expect(w, 0);
      expect(h, 0);
    });

    test('returns (0, 0) for empty bytes', () {
      final (w, h) = readPngDimensions(Uint8List(0));
      expect(w, 0);
      expect(h, 0);
    });
  });

  group('PageImageDecoded.hasDimensions', () {
    test('true when both dimensions are positive', () {
      expect(
        PageImageDecoded(bytes: Uint8List(0), width: 100, height: 200)
            .hasDimensions,
        isTrue,
      );
    });

    test('false when width is zero', () {
      expect(
        PageImageDecoded(bytes: Uint8List(0), width: 0, height: 200)
            .hasDimensions,
        isFalse,
      );
    });

    test('false when both are zero', () {
      expect(
        PageImageDecoded(bytes: Uint8List(0), width: 0, height: 0)
            .hasDimensions,
        isFalse,
      );
    });
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
}
