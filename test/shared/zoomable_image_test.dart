import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/zoomable_image.dart';

// 1x1 red PNG pixel (minimal valid PNG).
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
  '2mP8/58BAwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
);

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        // A bounded box mirroring the dialog/preview host so InteractiveViewer
        // has finite constraints and the image fills the viewport.
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

  testWidgets('enables trackpad-scroll zoom within scale bounds',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: _pngBytes,
        rotationQuarterTurns: 0,
        onRotate: () {},
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pump();

    // On the web, Flutter routes Mac trackpad two-finger scroll to a pan; with
    // the image filling the viewport that pan is clamped and nothing happens.
    // trackpadScrollCausesScale makes the gesture zoom instead.
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.trackpadScrollCausesScale, isTrue);
    expect(viewer.minScale, 1.0);
    expect(viewer.maxScale, 4.0);
  });

  testWidgets('reset control appears only while zoomed and restores fit',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: _pngBytes,
        rotationQuarterTurns: 0,
        onRotate: () {},
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pump();

    // Not zoomed: no reset control.
    expect(find.byTooltip('Reset zoom'), findsNothing);

    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    await tester.pump();

    // Zoomed: reset control shows; tapping it returns to the original fit.
    expect(find.byTooltip('Reset zoom'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();

    expect(controller.value, Matrix4.identity());
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });

  testWidgets('rotate button invokes onRotate', (tester) async {
    var rotations = 0;
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: _pngBytes,
        rotationQuarterTurns: 0,
        onRotate: () => rotations++,
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Rotate'));
    expect(rotations, 1);
  });

  testWidgets('applies the given quarter-turn rotation', (tester) async {
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: _pngBytes,
        rotationQuarterTurns: 3,
        onRotate: () {},
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pump();

    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 3);
  });

  testWidgets('shows fallback and hides rotate button on decode failure',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ZoomableImage(
        bytes: Uint8List.fromList(const [1, 2, 3, 4, 5]),
        rotationQuarterTurns: 0,
        onRotate: () {},
        decodeFailureChild: const Text('failed'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('failed'), findsOneWidget);
    expect(find.byTooltip('Rotate'), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
