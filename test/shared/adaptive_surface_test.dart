import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/adaptive_surface.dart';

void main() {
  Future<bool?> openAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    bool? builtAsDialog;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => presentAdaptively<void>(
              context,
              build: (asDialog) {
                builtAsDialog = asDialog;
                return const Center(child: Text('viewer'));
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    return builtAsDialog;
  }

  testWidgets('opens a dialog at tablet width', (tester) async {
    expect(await openAt(tester, 600), isTrue);
    expect(find.text('viewer'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);
  });

  testWidgets('pushes a page of its own below tablet width', (tester) async {
    expect(await openAt(tester, 599), isFalse);
    expect(find.text('viewer'), findsOneWidget);
    // A page replaces the opener rather than sitting over it.
    expect(find.text('open'), findsNothing);
  });

  testWidgets('the dialog is dismissed by its barrier', (tester) async {
    await openAt(tester, 800);
    await tester.tapAt(const Offset(795, 795));
    await tester.pump();
    expect(find.text('viewer'), findsNothing);
  });
}
