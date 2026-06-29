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
              Container(height: 80),
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

/// A short thread. With [withFollowUp] a *tall* follow-up question and a *short*
/// reply are appended; arriving as an update they pin the new question at the
/// top (as sending a message does), which sets the anchor that expands the
/// scroll extent past the content. A question taller than the (keyboard-shrunk)
/// viewport with too little reply below to fill it is exactly the case where a
/// plain jump-to-max re-pins the question and pushes the short reply — the
/// latest message — below the fold. The reply is tagged so the test can locate
/// it.
List<ChatMessage> _conversation({required bool withFollowUp}) {
  final filler = 'word ' * 40;
  final messages = <ChatMessage>[
    TextMessage(
      id: 'u-a',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'First question $filler',
    ),
    TextMessage(
      id: 'a-a',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 3, 1, 0, 1),
      text: 'First answer $filler',
    ),
  ];
  if (!withFollowUp) return messages;
  return [
    ...messages,
    TextMessage(
      id: 'u-b',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1, 0, 2),
      // Tall enough to fill the shrunk viewport on its own.
      text: 'Second question ${'word ' * 200}',
    ),
    TextMessage(
      id: 'a-b',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 3, 1, 0, 3),
      // Short: too little to fill the viewport below the pinned question.
      text: 'LATEST ASSISTANT REPLY',
    ),
  ];
}

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

  testWidgets('does not move a scrolled-up list when the inset stays zero',
      (tester) async {
    await tester.pumpWidget(_harness(_manyMessages(), 0));
    await tester.pumpAndSettle();

    // User scrolls up to read history.
    final position = _timelinePosition(tester);
    position.jumpTo(0);
    await tester.pump();
    expect(position.pixels, 0.0);

    // A rebuild with the inset still zero (no keyboard — i.e. desktop) must
    // not shrink the viewport, so the fix stays a no-op and the user's
    // position is preserved.
    await tester.pumpWidget(_harness(_manyMessages(), 0));
    await tester.pumpAndSettle();

    expect(_timelinePosition(tester).pixels, 0.0,
        reason: 'no viewport shrink => fix is a no-op; scroll position kept');
  });

  testWidgets(
      'leaves a list scrolled beyond the band in place when the '
      'keyboard opens', (tester) async {
    await tester.pumpWidget(_harness(_manyMessages(), 0));
    await tester.pumpAndSettle();

    // Scroll up well beyond the near-bottom band to read history.
    final position = _timelinePosition(tester);
    position.jumpTo(position.maxScrollExtent - 300);
    await tester.pump();
    final scrolledUp = _timelinePosition(tester).pixels;

    // Keyboard opens — the viewport shrinks — but the user is outside the
    // near-bottom band, so the re-pin guard must leave them where they are.
    await tester.pumpWidget(_harness(_manyMessages(), 300));
    await tester.pumpAndSettle();

    expect(_timelinePosition(tester).pixels, closeTo(scrolledUp, 1.0),
        reason: 'a list scrolled beyond the band is not yanked to the bottom '
            'when the keyboard opens');
  });

  testWidgets(
      'reveals the end of the latest reply over a top anchor when the '
      'keyboard opens', (tester) async {
    // Caught up on the first exchange.
    await tester.pumpWidget(_harness(_conversation(withFollowUp: false), 0));
    await tester.pumpAndSettle();

    // A follow-up question and its reply arrive; the new question is pinned to
    // the top, setting the anchor that expands maxScrollExtent past the content.
    await tester.pumpWidget(_harness(_conversation(withFollowUp: true), 0));
    await tester.pumpAndSettle();

    final anchored = _timelinePosition(tester);
    expect(anchored.maxScrollExtent - anchored.pixels, greaterThan(100.0),
        reason: 'the tall question is pinned at the top, so the rest position '
            'is above the bottom band (the reply hangs below the fold)');

    // Keyboard opens.
    await tester.pumpWidget(_harness(_conversation(withFollowUp: true), 300));
    await tester.pumpAndSettle();

    // The end of the latest reply is visible within the timeline viewport,
    // rather than the question staying pinned and the reply hiding behind the
    // keyboard.
    final replyFinder = find.textContaining('LATEST ASSISTANT REPLY');
    expect(replyFinder, findsOneWidget);
    final viewport = tester.getRect(find.byType(Scrollable).first);
    final replyRect = tester.getRect(replyFinder);
    expect(replyRect.bottom, lessThanOrEqualTo(viewport.bottom + 1.0),
        reason: 'the end of the latest reply sits within the visible viewport, '
            'instead of the tall question staying pinned and pushing the reply '
            'below the fold');
    expect(replyRect.bottom, greaterThan(viewport.top),
        reason: 'the latest reply is on-screen, not scrolled above the fold');
  });
}
