import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/message_timeline.dart';

void main() {
  testWidgets('renders text messages', (tester) async {
    final messages = [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Hello from user',
      ),
      TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'Hello from assistant',
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageTimeline(messages: messages, messageStates: const {}),
      ),
    ));

    expect(find.text('Hello from user'), findsOneWidget);
    expect(find.text('Hello from assistant'), findsOneWidget);
  });

  testWidgets('renders tool call messages', (tester) async {
    final messages = [
      ToolCallMessage(
        id: 'msg-tc',
        createdAt: DateTime(2026, 3, 1),
        toolCalls: [
          ToolCallInfo(
            id: 'tc-1',
            name: 'search',
            status: ToolCallStatus.completed,
            result: 'Found 3 results',
          ),
        ],
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageTimeline(messages: messages, messageStates: const {}),
      ),
    ));

    expect(find.text('search'), findsOneWidget);
  });

  testWidgets('renders error messages', (tester) async {
    final messages = [
      ErrorMessage(
        id: 'msg-err',
        createdAt: DateTime(2026, 3, 1),
        errorText: 'Something went wrong',
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageTimeline(messages: messages, messageStates: const {}),
      ),
    ));

    expect(find.text('Something went wrong'), findsOneWidget);
  });
}
