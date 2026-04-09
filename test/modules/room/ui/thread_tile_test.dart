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
