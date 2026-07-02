import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/mark_read_context_menu.dart';

void main() {
  Widget host({required VoidCallback? onMarkRead, String? title}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MarkReadContextMenu(
              onMarkRead: onMarkRead,
              title: title,
              child: const SizedBox(width: 44, height: 44, child: Text('R')),
            ),
          ),
        ),
      );

  testWidgets('long-press opens Mark as read and fires the callback',
      (tester) async {
    var marked = false;
    await tester.pumpWidget(host(onMarkRead: () => marked = true));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsOneWidget);

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(marked, isTrue);
  });

  testWidgets('secondary-tap (right-click) opens the menu and fires',
      (tester) async {
    var marked = false;
    await tester.pumpWidget(host(onMarkRead: () => marked = true));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('R')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsOneWidget);

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(marked, isTrue);
  });

  testWidgets('dismissing the menu without a selection does not fire',
      (tester) async {
    var marked = false;
    await tester.pumpWidget(host(onMarkRead: () => marked = true));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsOneWidget);

    // Tap the modal barrier outside the menu to dismiss it (returns null).
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsNothing);
    expect(marked, isFalse);
  });

  testWidgets('shows the title as a header above the action when provided',
      (tester) async {
    await tester.pumpWidget(host(onMarkRead: () {}, title: 'Beta'));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Mark as read'), findsOneWidget);
  });

  testWidgets('disabled (null callback): long-press opens no menu',
      (tester) async {
    await tester.pumpWidget(host(onMarkRead: null));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsNothing);
  });
}
