import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/zoomable_view.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        // A bounded box mirroring the dialog/preview host so the viewer has
        // finite constraints.
        body: Center(child: SizedBox(width: 400, height: 300, child: child)),
      ),
    );

InteractiveViewer _viewer(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

void main() {
  testWidgets('enables trackpad-scroll zoom (Mac web support)', (tester) async {
    // On Mac web, Flutter routes trackpad two-finger scroll to a pan; with the
    // content filling the viewport that pan is clamped and nothing happens.
    // This flag makes the gesture zoom instead. The gesture can't be simulated
    // in a widget test, so this assertion is the only guard against a silent
    // revert to the default (false).
    await tester.pumpWidget(_wrap(const ZoomableView(child: SizedBox())));

    expect(_viewer(tester).trackpadScrollCausesScale, isTrue);
  });

  testWidgets('panning is disabled at fit and enabled once zoomed',
      (tester) async {
    await tester.pumpWidget(_wrap(const ZoomableView(child: SizedBox())));

    // At fit the whole content is visible, so dragging it is meaningless.
    expect(_viewer(tester).panEnabled, isFalse);

    _viewer(tester).transformationController!.value =
        Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    await tester.pump();

    expect(_viewer(tester).panEnabled, isTrue);
  });

  testWidgets('reset control appears only while zoomed and restores fit',
      (tester) async {
    await tester.pumpWidget(_wrap(const ZoomableView(child: SizedBox())));

    expect(find.byTooltip('Reset zoom'), findsNothing);

    final controller = _viewer(tester).transformationController!;
    controller.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0);
    await tester.pump();

    expect(find.byTooltip('Reset zoom'), findsOneWidget);
    await tester.tap(find.byTooltip('Reset zoom'));
    await tester.pump();

    expect(controller.value, Matrix4.identity());
    expect(find.byTooltip('Reset zoom'), findsNothing);
  });

  testWidgets('rotate control is always shown and self-manages rotation',
      (tester) async {
    await tester.pumpWidget(_wrap(const ZoomableView(child: SizedBox())));

    expect(find.byTooltip('Rotate'), findsOneWidget);
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 0);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
  });

  testWidgets('rotate delegates to onRotate when provided (no self-rotation)',
      (tester) async {
    var rotations = 0;
    await tester.pumpWidget(_wrap(
      ZoomableView.controlledRotation(
        rotationQuarterTurns: 3,
        onRotate: () => rotations++,
        child: const SizedBox(),
      ),
    ));

    // The caller-supplied rotation is applied to the content.
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 3);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    expect(rotations, 1);
    // Caller owns rotation; the view does not rotate itself — it stays at the
    // caller's value until the caller updates it.
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 3);
  });
}
