import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/copy_button.dart';
import 'package:soliplex_frontend/src/modules/room/ui/feedback_buttons.dart';
import 'package:soliplex_frontend/src/modules/room/ui/text_message_tile.dart';

void main() {
  testWidgets('user message shows copy button but no feedback buttons',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextMessageTile(
            message: TextMessage(
              id: '1',
              user: ChatUser.user,
              createdAt: DateTime(2026),
              text: 'Hello',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsNothing);
  });

  testWidgets('assistant message shows copy button and feedback buttons',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextMessageTile(
            message: TextMessage(
              id: '2',
              user: ChatUser.assistant,
              createdAt: DateTime(2026),
              text: 'Hi there',
            ),
            runId: 'run-1',
            onFeedbackSubmit: (_, __) {},
          ),
        ),
      ),
    );

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsOneWidget);
  });

  testWidgets('assistant message without feedback callback shows only copy',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextMessageTile(
            message: TextMessage(
              id: '3',
              user: ChatUser.assistant,
              createdAt: DateTime(2026),
              text: 'Hi there',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CopyButton), findsOneWidget);
    expect(find.byType(FeedbackButtons), findsNothing);
  });

  testWidgets('thinking block shows copy button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextMessageTile(
            message: TextMessage(
              id: '4',
              user: ChatUser.assistant,
              createdAt: DateTime(2026),
              text: 'Response',
              thinkingText: 'Let me think about this...',
            ),
          ),
        ),
      ),
    );

    // One CopyButton for the message, one for the thinking block
    expect(find.byType(CopyButton), findsNWidgets(2));
  });
}
