import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/unread_boundary.dart';

Widget _harness(
  List<ChatMessage> messages, {
  StreamingState? streamingState,
}) {
  return ProviderScope(
    overrides: [
      messageExpansionsProvider.overrideWithValue(MessageExpansions()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          roomId: 'r',
          messages: messages,
          messageStates: const {},
          unreadBoundary: const BoundaryResolved(null),
          streamingState: streamingState,
        ),
      ),
    ),
  );
}

/// Tall messages first, short ones after. Read from the top, the list
/// estimates its extent from the tall tiles it has built, so the estimated end
/// lies far past the real one until the short tail is laid out.
List<ChatMessage> _tallThenShort() => [
      for (var i = 0; i < 6; i++)
        TextMessage(
          id: 'tall-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1).add(Duration(minutes: i)),
          text: 'Tall $i ${'word ' * 300}',
        ),
      for (var i = 0; i < 30; i++)
        TextMessage(
          id: 'short-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1, 1).add(Duration(minutes: i)),
          text: 'Short $i',
        ),
    ];

/// Short messages first, then ones growing taller. Read from the top, the
/// list estimates its extent from the short tiles it has built, so the
/// estimated end falls short of the real one; each jump there lays out tiles
/// still shorter than the ones beyond them.
List<ChatMessage> _shortThenGrowing() => [
      for (var i = 0; i < 200; i++)
        TextMessage(
          id: 'short-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1).add(Duration(minutes: i)),
          text: 'Short $i',
        ),
      for (var i = 0; i < 12; i++)
        TextMessage(
          id: 'growing-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 2).add(Duration(minutes: i)),
          text: 'Growing $i ${'word ' * (40 << i)}',
        ),
    ];

/// Two slightly taller messages first. Read from the top, the list
/// overestimates its end by less than a screen, so the jump there lands past
/// the end with the question's tile still laid out.
List<ChatMessage> _slightlyTallFirst() => [
      for (var i = 0; i < 60; i++)
        TextMessage(
          id: 'm-$i',
          user: i.isEven ? ChatUser.user : ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1).add(Duration(minutes: i)),
          text: i < 2 ? 'Tall $i ${'word ' * 10}' : 'Short $i',
        ),
    ];

/// Plays the web engine's part when the accessibility tree is on: it mirrors
/// the scroll view in a DOM scroll container that cannot sit past the end, so
/// a position reported past the end comes back as a scroll to the end.
void _echoClampedPosition(WidgetTester tester) {
  final position = _timelinePosition(tester);
  if (position.pixels <= position.maxScrollExtent) return;
  final owner = tester.getSemantics(find.byType(Scrollable).first).owner!;
  final scrollers = <SemanticsNode>[];
  bool collect(SemanticsNode node) {
    if (node.getSemanticsData().hasAction(SemanticsAction.scrollToOffset)) {
      scrollers.add(node);
    }
    node.visitChildren(collect);
    return true;
  }

  collect(owner.rootSemanticsNode!);
  owner.performAction(
    scrollers.single.id,
    SemanticsAction.scrollToOffset,
    Float64List.fromList([0, position.maxScrollExtent]),
  );
}

const _question = TextMessage(
  id: 'sent',
  user: ChatUser.user,
  createdAt: null,
  text: 'THE SENT QUESTION',
);

ScrollPosition _timelinePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// Sends [_question] after [history], read from the top, and expects the
/// question pinned at the top of the viewport.
Future<void> _expectPinnedAfterSendingFromTop(
  WidgetTester tester,
  List<ChatMessage> history,
) async {
  await tester.pumpWidget(_harness(history));
  await tester.pumpAndSettle();

  // The reader scrolls back to the top, out of reach of the tail tiles.
  _timelinePosition(tester).jumpTo(0);
  await tester.pumpAndSettle();
  expect(find.text('THE SENT QUESTION'), findsNothing);

  // Sending starts a run, whose loading tile follows the question.
  await tester.pumpWidget(_harness(
    [...history, _question],
    streamingState: const AwaitingText(),
  ));
  // The loading tile animates for as long as the run lasts, so the list
  // never settles; pump frames enough for the pin and its scroll animation.
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }

  final question = find.text('THE SENT QUESTION');
  expect(question, findsOneWidget,
      reason: 'the sent question is on screen, not left below the fold');
  final viewport = tester.getRect(find.byType(Scrollable).first);
  final questionTop = tester.getRect(question).top;
  expect(questionTop - viewport.top, lessThan(100.0),
      reason: 'the sent question sits at the top of the viewport');
}

void main() {
  testWidgets(
      'pins the sent question at the top when the list overestimates its end',
      (tester) async {
    await _expectPinnedAfterSendingFromTop(tester, _tallThenShort());
  });

  testWidgets(
      'pins the sent question at the top when the list underestimates its end',
      (tester) async {
    await _expectPinnedAfterSendingFromTop(tester, _shortThenGrowing());
  });

  testWidgets(
      'pins the sent question at the top when the accessibility tree pulls '
      'the list back from past its end', (tester) async {
    final semantics = tester.ensureSemantics();
    // Disposed in the body: the framework checks for live handles before
    // tear-downs run.
    try {
      final history = _slightlyTallFirst();
      await tester.pumpWidget(_harness(history));
      await tester.pumpAndSettle();
      _timelinePosition(tester).jumpTo(0);
      await tester.pumpAndSettle();

      await tester.pumpWidget(_harness(
        [...history, _question],
        streamingState: const AwaitingText(),
      ));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        _echoClampedPosition(tester);
      }

      final viewport = tester.getRect(find.byType(Scrollable).first);
      final questionTop = tester.getRect(find.text('THE SENT QUESTION')).top;
      expect(questionTop - viewport.top, lessThan(100.0),
          reason: 'the sent question sits at the top of the viewport');
    } finally {
      semantics.dispose();
    }
  });
}
