import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

/// Builds a timeline that rests at the bottom (caught-up, no unread divider)
/// inside a Scaffold whose wrapping MediaQuery carries [bottomInset]. The
/// Scaffold consumes the inset and shrinks the body, exactly as a real
/// keyboard does; a fixed-height stand-in plays the role of the input bar.
Widget _harness(List<ChatMessage> messages, double bottomInset) {
  return ProviderScope(
    overrides: [
      messageExpansionsProvider.overrideWithValue(MessageExpansions()),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: MessageTimeline(
                  roomId: 'r',
                  messages: messages,
                  messageStates: const {},
                  unreadBoundary: const BoundaryResolved(null),
                ),
              ),
              Container(height: 80, color: const Color(0xFF888888)),
            ],
          ),
        ),
      ),
    ),
  );
}

List<ChatMessage> _manyMessages() => [
      for (var i = 0; i < 40; i++)
        TextMessage(
          id: 'msg-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1).add(Duration(minutes: i)),
          text: 'Message number $i with some text to take vertical space',
        ),
    ];

ScrollPosition _timelinePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('keeps the latest message visible when the keyboard opens',
      (tester) async {
    await tester.pumpWidget(_harness(_manyMessages(), 0));
    await tester.pumpAndSettle();

    final atRest = _timelinePosition(tester);
    expect(atRest.pixels, closeTo(atRest.maxScrollExtent, 1.0),
        reason: 'caught-up timeline rests at the bottom');

    // Keyboard opens: the wrapping MediaQuery gains a bottom inset, the
    // Scaffold shrinks the body, and the timeline's viewport shrinks with it.
    await tester.pumpWidget(_harness(_manyMessages(), 300));
    await tester.pumpAndSettle();

    final afterKeyboard = _timelinePosition(tester);
    expect(
        afterKeyboard.maxScrollExtent - afterKeyboard.pixels, lessThan(100.0),
        reason: 'list re-pins to the bottom so the latest message stays '
            'visible above the input instead of hiding behind the keyboard');
  });
}
