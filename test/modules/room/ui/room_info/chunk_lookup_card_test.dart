import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/chunk_visualization_page.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info/chunk_lookup_card.dart';

import '../../../../helpers/fakes.dart';

class _ChunkVizApi extends FakeSoliplexApi {
  @override
  Future<ChunkVisualization> getChunkVisualization(
    String roomId,
    String chunkId, {
    List<String>? refs,
    bool expand = true,
    CancelToken? cancelToken,
  }) async =>
      ChunkVisualization(
        chunkId: chunkId,
        documentUri: null,
        imagesBase64: const [],
      );
}

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  Finder viewButton() => find.widgetWithText(FilledButton, 'View chunk');

  testWidgets('View chunk is disabled until a non-blank id is entered',
      (tester) async {
    await tester.pumpWidget(wrap(
      ChunkLookupCard(api: _ChunkVizApi(), roomId: 'room-1'),
    ));

    expect(tester.widget<FilledButton>(viewButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(viewButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'chunk-42');
    await tester.pump();
    expect(tester.widget<FilledButton>(viewButton()).onPressed, isNotNull);
  });

  testWidgets('tapping View chunk opens the visualization with the trimmed id',
      (tester) async {
    await tester.pumpWidget(wrap(
      ChunkLookupCard(api: _ChunkVizApi(), roomId: 'room-1'),
    ));

    await tester.enterText(find.byType(TextField), '  chunk-42  ');
    await tester.pump();
    await tester.tap(viewButton());
    await tester.pump();

    final page = tester.widget<ChunkVisualizationPage>(
      find.byType(ChunkVisualizationPage),
    );
    expect(page.chunkId, 'chunk-42');
    expect(page.roomId, 'room-1');
  });
}
