import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/ui/day_divider.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

TextMessage _msg(String id, DateTime createdAt) => TextMessage(
      id: id,
      user: ChatUser.assistant,
      createdAt: createdAt,
      text: 'body-$id',
    );

TextMessage _pending(String id) => TextMessage(
      id: id,
      user: ChatUser.user,
      createdAt: null,
      text: 'body-$id',
    );

Widget _harness(List<ChatMessage> messages) => MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          roomId: 'room-1',
          messages: messages,
          messageStates: const {},
          unreadBoundary: const BoundaryResolved(null),
        ),
      ),
    );

void main() {
  testWidgets('a divider marks each calendar-day group (first + boundaries)',
      (tester) async {
    // Two messages on different days → a divider above the first, and one
    // before the second where the day changes.
    await tester.pumpWidget(_harness([
      _msg('a', DateTime(2020, 3, 3, 9)),
      _msg('b', DateTime(2020, 3, 4, 9)),
    ]));
    await tester.pump();

    expect(find.byType(DayDivider), findsNWidgets(2));
  });

  testWidgets('no divider between two messages on the same calendar day',
      (tester) async {
    // Same day → only the leading divider above the first message.
    await tester.pumpWidget(_harness([
      _msg('a', DateTime(2020, 3, 3, 9)),
      _msg('b', DateTime(2020, 3, 3, 15)),
    ]));
    await tester.pump();

    expect(find.byType(DayDivider), findsOneWidget);
  });

  testWidgets('a pending message (null createdAt) groups under today',
      (tester) async {
    // The in-flight user echo carries no time until RUN_STARTED; it must not
    // crash the day grouping and falls under today's group alongside a message
    // already stamped today.
    await tester.pumpWidget(_harness([
      _msg('a', DateTime.now()),
      _pending('b'),
    ]));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DayDivider), findsOneWidget);
  });
}
