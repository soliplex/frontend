import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';

TextMessage _msg(String id) =>
    TextMessage.create(id: id, user: ChatUser.assistant, text: 'body-$id');

void main() {
  Widget harness({String? boundary, bool resolved = true}) => MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'room-1',
            messages: [_msg('a'), _msg('b'), _msg('c')],
            messageStates: const {},
            unreadBoundaryId: boundary,
            unreadBoundaryResolved: resolved,
          ),
        ),
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
}
