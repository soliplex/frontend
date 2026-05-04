import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/thread_tile.dart';

void main() {
  final thread = ThreadInfo(
    id: 't-1',
    roomId: 'room-1',
    name: 'Test Thread',
    createdAt: DateTime(2026, 3, 1),
  );

  testWidgets('renders "New Thread" for a thread with no name', (tester) async {
    final nameless = ThreadInfo(
      id: 't-2',
      roomId: 'room-1',
      createdAt: DateTime(2026, 3, 1),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: nameless,
          isSelected: false,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ));

    expect(find.text('New Thread'), findsOneWidget);
  });

  testWidgets('overflow menu shows Rename and Delete options', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('tapping Rename fires onRename callback', (tester) async {
    bool renameCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          onTap: () {},
          onRename: () => renameCalled = true,
          onDelete: () {},
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renameCalled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping Delete fires onDelete callback', (tester) async {
    bool deleteCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          onTap: () {},
          onRename: () {},
          onDelete: () => deleteCalled = true,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'on desktop, non-selected thread: tapping Rename still fires callback '
      'after the tile is no longer hovered (menu opens on the overlay, '
      'the PopupMenuButton must stay mounted until the user picks an item)',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    bool renameCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: ThreadTile(
              thread: thread,
              isSelected: false,
              onTap: () {},
              onRename: () => renameCalled = true,
              onDelete: () {},
            ),
          ),
        ),
      ),
    ));

    // Simulate pointer hover to reveal the menu button on desktop.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(ThreadTile)));
    await tester.pumpAndSettle();

    // Tap the overflow icon to open the popup menu.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Opening the popup moves the pointer onto the overlay, so the tile's
    // MouseRegion fires onExit. Simulate that.
    await gesture.moveTo(const Offset(1000, 1000));
    await tester.pump();

    // Now pick Rename. If the PopupMenuButton was unmounted by the hover
    // loss, onSelected (and therefore onRename) would never fire.
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renameCalled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'on desktop, non-selected thread: tapping Delete still fires callback '
      'after the tile is no longer hovered', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    bool deleteCalled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: ThreadTile(
              thread: thread,
              isSelected: false,
              onTap: () {},
              onRename: () {},
              onDelete: () => deleteCalled = true,
            ),
          ),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(ThreadTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    await gesture.moveTo(const Offset(1000, 1000));
    await tester.pump();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleteCalled, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mobile: spinner replaces menu when isRunning', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          isRunning: true,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop hover: spinner replaces menu when isRunning',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: ThreadTile(
              thread: thread,
              isSelected: false,
              isRunning: true,
              onTap: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(ThreadTile)));
    // Spinner animates indefinitely; pump a frame instead of settling.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'renders no trailing widget when not running and not selected/hovered '
      '(desktop)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Delete menu item uses error color', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadTile(
          thread: thread,
          isSelected: false,
          onTap: () {},
          onRename: () {},
          onDelete: () {},
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final deleteIcon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
    final theme = Theme.of(tester.element(find.text('Delete')));
    expect(deleteIcon.color, theme.colorScheme.error);
  });
}
