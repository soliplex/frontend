import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/text_message_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/tool_call_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/error_message_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/gen_ui_tile.dart';
import 'package:soliplex_frontend/src/modules/room/ui/loading_message_tile.dart';

void main() {
  group('TextMessageTile', () {
    testWidgets('shows user label for user messages', (tester) async {
      final msg = TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Hello',
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TextMessageTile(message: msg))));
      expect(find.text('You'), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('shows assistant label for assistant messages', (tester) async {
      final msg = TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'Response',
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TextMessageTile(message: msg))));
      expect(find.text('Assistant'), findsOneWidget);
    });

    testWidgets('shows thinking text when present', (tester) async {
      final msg = TextMessage(
        id: 'msg-3',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'Response',
        thinkingText: 'Thinking about this...',
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TextMessageTile(message: msg))));
      expect(find.text('Thinking...'), findsOneWidget);
    });
  });

  group('ToolCallTile', () {
    testWidgets('shows tool name and status', (tester) async {
      final msg = ToolCallMessage(
        id: 'msg-tc',
        createdAt: DateTime(2026, 3, 1),
        toolCalls: [
          ToolCallInfo(
            id: 'tc-1',
            name: 'get_weather',
            status: ToolCallStatus.completed,
            result: '{"temp": 68}',
          ),
        ],
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ToolCallTile(message: msg))));
      expect(find.text('get_weather'), findsOneWidget);
      expect(find.text('completed'), findsOneWidget);
    });

    testWidgets('expands to show args and result on tap', (tester) async {
      final msg = ToolCallMessage(
        id: 'msg-tc',
        createdAt: DateTime(2026, 3, 1),
        toolCalls: [
          ToolCallInfo(
            id: 'tc-1',
            name: 'search',
            arguments: '{"query": "test"}',
            status: ToolCallStatus.completed,
            result: 'Found results',
          ),
        ],
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ToolCallTile(message: msg))));
      expect(find.text('Found results'), findsNothing);
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();
      expect(find.text('Found results'), findsOneWidget);
    });
  });

  group('ErrorMessageTile', () {
    testWidgets('shows error text', (tester) async {
      final msg = ErrorMessage(
        id: 'msg-err',
        createdAt: DateTime(2026, 3, 1),
        errorText: 'Something broke',
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: ErrorMessageTile(message: msg))));
      expect(find.text('Something broke'), findsOneWidget);
    });
  });

  group('GenUiTile', () {
    testWidgets('shows widget name and data', (tester) async {
      final msg = GenUiMessage(
        id: 'msg-gui',
        createdAt: DateTime(2026, 3, 1),
        widgetName: 'quiz_card',
        data: {'question': 'What is 2+2?'},
      );
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: GenUiTile(message: msg))));
      expect(find.text('quiz_card'), findsOneWidget);
    });
  });

  group('LoadingMessageTile', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: LoadingMessageTile())));
      expect(find.byType(LoadingMessageTile), findsOneWidget);
    });
  });
}
