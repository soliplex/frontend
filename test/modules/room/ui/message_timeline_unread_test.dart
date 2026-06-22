import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/ui/unread_divider.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

TextMessage _msg(String id) =>
    TextMessage.create(id: id, user: ChatUser.assistant, text: 'body-$id');

void main() {
  Widget harnessWith({
    required List<ChatMessage> messages,
    String? boundary,
    bool resolved = true,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'room-1',
            messages: messages,
            messageStates: const {},
            unreadBoundary:
                resolved ? BoundaryResolved(boundary) : const BoundaryPending(),
          ),
        ),
      );

  Widget harness({String? boundary, bool resolved = true}) => harnessWith(
        messages: [_msg('a'), _msg('b'), _msg('c')],
        boundary: boundary,
        resolved: resolved,
      );

  testWidgets('shows the divider when a boundary is set', (tester) async {
    await tester.pumpWidget(harness(boundary: 'a'));
    await tester.pump();
    expect(find.text('New messages'), findsOneWidget);
  });

  testWidgets('shows no divider when no boundary', (tester) async {
    await tester.pumpWidget(harness(boundary: null));
    await tester.pump();
    expect(find.text('New messages'), findsNothing);
  });

  testWidgets('shows no divider when the boundary is the last message',
      (tester) async {
    await tester.pumpWidget(harness(boundary: 'c'));
    await tester.pump();
    expect(find.text('New messages'), findsNothing);
  });

  testWidgets('shows no divider until the boundary is resolved',
      (tester) async {
    await tester.pumpWidget(harness(boundary: 'a', resolved: false));
    await tester.pump();
    expect(find.text('New messages'), findsNothing);
  });

  testWidgets(
      'caught up: a live message does not pop in a divider (freeze holds)',
      (tester) async {
    // Boundary is the last message → caught up → no divider once resolved.
    await tester.pumpWidget(harnessWith(
      messages: [_msg('a'), _msg('b'), _msg('c')],
      boundary: 'c',
    ));
    await tester.pump();
    expect(find.text('New messages'), findsNothing);

    // A new message arrives live. The boundary was evaluated once and frozen,
    // so no divider may appear above the newly-arrived message.
    await tester.pumpWidget(harnessWith(
      messages: [_msg('a'), _msg('b'), _msg('c'), _msg('d')],
      boundary: 'c',
    ));
    await tester.pump();
    expect(find.text('New messages'), findsNothing);
  });

  testWidgets('does not scroll while the unread boundary is pending',
      (tester) async {
    // Enough messages to overflow the viewport so an initial scroll is
    // observable as a non-zero offset.
    final messages = [for (var i = 0; i < 30; i++) _msg('m$i')];
    await tester.pumpWidget(harnessWith(
      messages: messages,
      boundary: 'm0',
      resolved: false,
    ));
    await tester.pumpAndSettle();

    // While the boundary is unresolved the timeline can't yet know whether to
    // land at the bottom (caught up) or at the divider (unread), so it must not
    // scroll at all. Landing at the bottom now would yank the view once the
    // boundary resolves to an unread line.
    final controller = tester
        .widgetList<CustomScrollView>(find.byType(CustomScrollView))
        .first
        .controller!;
    expect(controller.offset, 0);
  });

  testWidgets('renders the divider above the first unread tile',
      (tester) async {
    // boundary 'a' → first unread is 'b' (tile index 1).
    await tester.pumpWidget(harness(boundary: 'a'));
    await tester.pump();

    final tiles = find.byType(MessageTile);
    final dividerY = tester.getTopLeft(find.byType(UnreadDivider)).dy;
    expect(dividerY, greaterThan(tester.getTopLeft(tiles.at(0)).dy));
    expect(dividerY, lessThan(tester.getTopLeft(tiles.at(1)).dy));
  });
}
