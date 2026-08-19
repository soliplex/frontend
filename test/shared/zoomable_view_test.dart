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

int _quarterTurns(WidgetTester tester) =>
    tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns;

/// Pumps a host that opens the media dialog on tap, then opens it.
Future<void> _openMediaDialog(WidgetTester tester, {Widget? caption}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showZoomableMediaDialog(
              context,
              viewer: const ZoomableView(child: SizedBox()),
              caption: caption,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

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
    expect(_quarterTurns(tester), 0);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    expect(_quarterTurns(tester), 1);
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
    expect(_quarterTurns(tester), 3);

    await tester.tap(find.byTooltip('Rotate'));
    await tester.pump();

    expect(rotations, 1);
    // Caller owns rotation; the view does not rotate itself — it stays at the
    // caller's value until the caller updates it.
    expect(_quarterTurns(tester), 3);
  });

  testWidgets('media dialog close control dismisses without shadowing rotate',
      (tester) async {
    await _openMediaDialog(tester);
    expect(find.byType(Dialog), findsOneWidget);

    // The dialog's close control sits over the viewer, so it can swallow taps
    // meant for the viewer's own controls. Rotating has to still rotate, and
    // must not dismiss.
    await tester.tap(find.byTooltip('Rotate'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(_quarterTurns(tester), 1);

    // The barrier dismisses as well; the button is the affordance a pointer or
    // screen reader user can find.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('media dialog shows the caption beneath the viewer',
      (tester) async {
    await _openMediaDialog(tester, caption: const Text('figure 1'));

    expect(find.text('figure 1'), findsOneWidget);
  });
}
