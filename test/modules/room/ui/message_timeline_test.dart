import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';

void main() {
  testWidgets('renders messages normally when non-empty', (tester) async {
    final message = TextMessage(
      id: 'msg-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: MessageTimeline(
            roomId: 'r',
            messages: [message],
            messageStates: const {},
          ),
        ),
      ),
    ));

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets(
    'renders surrounding messages when one tile throws during build',
    (tester) async {
      // One bad tile must not take down the rest of the chat history. We
      // simulate a build-time failure by injecting an executionTrackers
      // map whose `[]` throws when looked up with the offending id; that
      // lookup happens per-tile inside the timeline's itemBuilder.
      final good1 = TextMessage(
        id: 'good-before',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'before',
      );
      final bad = TextMessage(
        id: 'bad',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1, 0, 1),
        text: 'bad-message-text',
      );
      final good2 = TextMessage(
        id: 'good-after',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1, 0, 2),
        text: 'after',
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(MessageExpansions()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageTimeline(
              roomId: 'r',
              messages: [good1, bad, good2],
              messageStates: const {},
              executionTrackers: _ExecutionTrackersThrowingOnId('bad'),
            ),
          ),
        ),
      ));

      expect(find.text('before'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
      expect(
        find.textContaining('Could not render message bad'),
        findsOneWidget,
      );
    },
  );
}

/// An `executionTrackers` map whose `[]` throws for one specific id but
/// behaves like an empty map otherwise. Used to simulate a synchronous
/// build-time failure for a single tile.
class _ExecutionTrackersThrowingOnId extends MapBase<String, ExecutionTracker> {
  _ExecutionTrackersThrowingOnId(this._failingId);

  final String _failingId;

  @override
  ExecutionTracker? operator [](Object? key) {
    if (key == _failingId) {
      throw StateError('induced failure for tile $_failingId');
    }
    return null;
  }

  @override
  void operator []=(String key, ExecutionTracker value) {
    throw UnsupportedError('read-only');
  }

  @override
  void clear() {
    throw UnsupportedError('read-only');
  }

  @override
  Iterable<String> get keys => const Iterable.empty();

  @override
  ExecutionTracker? remove(Object? key) {
    throw UnsupportedError('read-only');
  }
}
