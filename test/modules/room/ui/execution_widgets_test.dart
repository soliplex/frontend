import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/activity_indicator.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/step_log.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';

void main() {
  testWidgets('ActivityIndicator shows Processing label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ActivityIndicator(activity: ProcessingActivity()),
      ),
    ));

    expect(find.text('Processing...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('ActivityIndicator shows tool call label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ActivityIndicator(
          activity: ToolCallActivity(toolName: 'search_docs'),
        ),
      ),
    ));

    expect(find.text('Calling search_docs...'), findsOneWidget);
  });

  testWidgets('ActivityIndicator shows Thinking label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ActivityIndicator(activity: ThinkingActivity()),
      ),
    ));

    expect(find.text('Thinking...'), findsOneWidget);
  });

  testWidgets('ActivityIndicator shows Responding label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ActivityIndicator(activity: RespondingActivity()),
      ),
    ));

    expect(find.text('Responding...'), findsOneWidget);
  });

  testWidgets('StepLog shows step count', (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(executionEvents: events);

    events.value = const ThinkingStarted();
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StepLog(tracker: tracker),
      ),
    ));

    expect(find.text('2 tool calls'), findsOneWidget);

    tracker.dispose();
  });

  testWidgets('ExecutionThinkingBlock shows thinking label', (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(executionEvents: events);

    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'Let me think about this');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExecutionThinkingBlock(tracker: tracker),
      ),
    ));

    expect(find.text('Thinking'), findsOneWidget);

    tracker.dispose();
  });
}
