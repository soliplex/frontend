import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/streaming_tile.dart';

void main() {
  testWidgets('renders activity indicator for AwaitingText', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: AwaitingText()),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Processing...'), findsOneWidget);
  });

  testWidgets('renders streamed text for TextStreaming', (tester) async {
    const streaming = TextStreaming(
      messageId: 'msg-1',
      user: ChatUser.assistant,
      text: 'Hello world',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: streaming),
      ),
    ));

    expect(find.text('Hello world'), findsOneWidget);
  });

  testWidgets('renders placeholder for empty TextStreaming', (tester) async {
    const streaming = TextStreaming(
      messageId: 'msg-1',
      user: ChatUser.assistant,
      text: '',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: streaming),
      ),
    ));

    expect(find.text('...'), findsOneWidget);
  });

  testWidgets('renders activity label from StreamingState.currentActivity',
      (tester) async {
    const streaming = AwaitingText(
      currentActivity: ToolCallActivity(toolName: 'search_docs'),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: streaming),
      ),
    ));

    expect(find.text('Calling search_docs...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('renders Thinking activity label', (tester) async {
    const streaming = AwaitingText(
      currentActivity: ThinkingActivity(),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: streaming),
      ),
    ));

    expect(find.text('Thinking...'), findsOneWidget);
  });

  testWidgets('renders Responding activity label during TextStreaming',
      (tester) async {
    const streaming = TextStreaming(
      messageId: 'msg-1',
      user: ChatUser.assistant,
      text: 'Hello',
      currentActivity: RespondingActivity(),
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StreamingTile(streamingState: streaming),
      ),
    ));

    expect(find.text('Responding...'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('renders step log when executionTracker has steps',
      (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(executionEvents: events);

    events.value = const ThinkingStarted();
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    const streaming = AwaitingText(
      currentActivity: ToolCallActivity(toolName: 'search'),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreamingTile(
          streamingState: streaming,
          executionTracker: tracker,
        ),
      ),
    ));

    expect(find.text('2 steps'), findsOneWidget);

    tracker.dispose();
  });

  testWidgets('renders thinking block when tracker has thinking text',
      (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(executionEvents: events);

    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'Let me think about this');

    const streaming = AwaitingText(
      currentActivity: ThinkingActivity(),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreamingTile(
          streamingState: streaming,
          executionTracker: tracker,
        ),
      ),
    ));

    expect(find.text('Thinking'), findsOneWidget);

    tracker.dispose();
  });
}
