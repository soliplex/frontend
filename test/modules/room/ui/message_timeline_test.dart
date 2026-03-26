import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';

void main() {
  testWidgets('renders welcome message when messages empty and room loaded',
      (tester) async {
    const room = Room(
      id: 'room-1',
      name: 'Research Bot',
      welcomeMessage: 'Welcome! Ask me anything.',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          messages: [],
          messageStates: {},
          room: room,
          onSuggestionTapped: null,
        ),
      ),
    ));

    expect(find.text('Research Bot'), findsOneWidget);
    expect(find.text('Welcome! Ask me anything.'), findsOneWidget);
  });

  testWidgets('renders suggestion chips when room has suggestions',
      (tester) async {
    const room = Room(
      id: 'room-1',
      name: 'Bot',
      suggestions: ['Suggestion A', 'Suggestion B'],
    );

    bool tappedSuggestion = false;
    String? tappedText;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          messages: const [],
          messageStates: const {},
          room: room,
          onSuggestionTapped: (text) {
            tappedSuggestion = true;
            tappedText = text;
          },
        ),
      ),
    ));

    expect(find.text('Suggestion A'), findsOneWidget);
    expect(find.text('Suggestion B'), findsOneWidget);

    await tester.tap(find.text('Suggestion A'));
    expect(tappedSuggestion, isTrue);
    expect(tappedText, 'Suggestion A');
  });

  testWidgets('renders fallback when no room data', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          messages: [],
          messageStates: {},
          room: null,
          onSuggestionTapped: null,
        ),
      ),
    ));

    expect(find.text('Type a message to get started'), findsOneWidget);
  });

  testWidgets('renders messages normally when non-empty', (tester) async {
    final message = TextMessage(
      id: 'msg-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
    );

    const room = Room(
      id: 'room-1',
      name: 'Bot',
      welcomeMessage: 'Welcome!',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageTimeline(
          messages: [message],
          messageStates: const {},
          room: room,
          onSuggestionTapped: null,
        ),
      ),
    ));

    expect(find.text('Welcome!'), findsNothing);
    expect(find.text('Hello'), findsOneWidget);
  });
}
