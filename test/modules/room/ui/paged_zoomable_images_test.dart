import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/paged_zoomable_images.dart';
import 'package:soliplex_frontend/src/modules/room/ui/pager_dots.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 400, height: 400, child: child)),
      ),
    );

void main() {
  testWidgets('persists per-page rotation across paging', (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 3,
        pageBuilder: (context, index, rotation) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('page$index rot${rotation.quarterTurns}'),
              TextButton(
                  onPressed: rotation.onRotate, child: Text('rot$index')),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Rotate page 0 twice.
    expect(find.text('page0 rot0'), findsOneWidget);
    await tester.tap(find.text('rot0'));
    await tester.pump();
    await tester.tap(find.text('rot0'));
    await tester.pump();
    expect(find.text('page0 rot2'), findsOneWidget);

    // Swipe to page 1 — its rotation is independent.
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('page1 rot0'), findsOneWidget);

    // Swipe back to page 0 — its rotation persisted.
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('page0 rot2'), findsOneWidget);
  });

  testWidgets('hides page dots and chevrons for a single item', (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 1,
        pageBuilder: (context, index, _) => Center(child: Text('page$index')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('page0'), findsOneWidget);
    expect(find.byType(PagerDots), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('opens at the given initialIndex', (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 3,
        initialIndex: 1,
        pageBuilder: (context, index, _) => Center(child: Text('page$index')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('page1'), findsOneWidget);
  });

  testWidgets('footer follows the current page', (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 3,
        // Arrow-key paging needs focus, which a dialog host grants via autofocus.
        autofocus: true,
        pageBuilder: (context, index, _) => Center(child: Text('page$index')),
        footerBuilder: (context, index) => Text('footer$index'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('footer0'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('footer1'), findsOneWidget);
  });

  testWidgets('left/right arrow keys page between items, clamped at the ends',
      (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 3,
        autofocus: true,
        pageBuilder: (context, index, _) => Center(child: Text('page$index')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('page0'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('page1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('page0'), findsOneWidget);

    // Arrow-left at the first page is clamped — stays on page 0.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('page0'), findsOneWidget);
  });

  testWidgets('prev/next chevrons page and disable at the ends',
      (tester) async {
    await tester.pumpWidget(_host(
      PagedZoomableImages(
        itemCount: 3,
        pageBuilder: (context, index, _) => Center(child: Text('page$index')),
      ),
    ));
    await tester.pumpAndSettle();

    IconButton chevron(IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    // First page: Previous disabled, Next enabled.
    expect(chevron(Icons.chevron_left).onPressed, isNull);
    expect(chevron(Icons.chevron_right).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    // Last page: Next disabled, Previous enabled.
    expect(find.text('page2'), findsOneWidget);
    expect(chevron(Icons.chevron_right).onPressed, isNull);
    expect(chevron(Icons.chevron_left).onPressed, isNotNull);
  });
}
