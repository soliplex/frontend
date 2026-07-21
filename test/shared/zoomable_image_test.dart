import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/zoomable_image.dart';
import 'package:soliplex_frontend/src/shared/zoomable_view.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        // A bounded box mirroring the dialog/preview host so the viewer has
        // finite constraints and the image fills the viewport.
        body: Center(child: SizedBox(width: 400, height: 300, child: child)),
      ),
    );

void main() {
  // The same bytes are a shared imageCache key; clear it between tests so a
  // decode result from one test can't poison the next.
  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  testWidgets('shows fallback and hides the viewer on decode failure',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: Uint8List.fromList(const [1, 2, 3, 4, 5]),
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('failed'), findsOneWidget);
    expect(find.byType(ZoomableView), findsNothing);
    expect(find.byTooltip('Rotate'), findsNothing);
  });

  testWidgets(
      'a provider that fails to load shows the fallback without zoom/rotate '
      'chrome', (tester) async {
    // A provider-backed image (network/asset/file in the zoom dialog) whose
    // load fails must own the failure the same way the bytes path does: the
    // fallback replaces the viewer, so there is no rotate button hovering over
    // a broken image. Undecodable bytes via MemoryImage stand in for a failing
    // provider without needing the network.
    await tester.pumpWidget(_wrap(
      ZoomableImage.provider(
        MemoryImage(Uint8List.fromList(const [1, 2, 3, 4, 5])),
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('failed'), findsOneWidget);
    expect(find.byType(ZoomableView), findsNothing);
    expect(find.byTooltip('Rotate'), findsNothing);
  });
}
