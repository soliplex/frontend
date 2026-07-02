import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/mark_read_context_menu.dart';

void main() {
  testWidgets('long-press opens Mark as read and fires the callback',
      (tester) async {
    var marked = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MarkReadContextMenu(
            enabled: true,
            onMarkRead: () => marked = true,
            child: const SizedBox(width: 44, height: 44, child: Text('R')),
          ),
        ),
      ),
    ));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsOneWidget);

    await tester.tap(find.text('Mark as read'));
    await tester.pumpAndSettle();
    expect(marked, isTrue);
  });

  testWidgets('disabled: long-press opens no menu', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MarkReadContextMenu(
            enabled: false,
            onMarkRead: () {},
            child: const SizedBox(width: 44, height: 44, child: Text('R')),
          ),
        ),
      ),
    ));

    await tester.longPress(find.text('R'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as read'), findsNothing);
  });
}
