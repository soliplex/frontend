import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../helpers/test_logger.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/phase_indicator.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';

Widget _withStore(Widget child) => ProviderScope(
      overrides: [
        messageExpansionsProvider.overrideWithValue(MessageExpansions()),
      ],
      child: child,
    );

void main() {
  testWidgets('PhaseIndicator shows Processing label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PhaseIndicator(phase: ProcessingPhase()),
      ),
    ));

    expect(find.text('Processing...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('PhaseIndicator shows tool call label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhaseIndicator(
          phase: ToolCallPhase.single(toolName: 'search_docs'),
        ),
      ),
    ));

    expect(find.text('Calling search_docs...'), findsOneWidget);
  });

  testWidgets('PhaseIndicator shows Thinking label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PhaseIndicator(phase: ThinkingPhase()),
      ),
    ));

    expect(find.text('Thinking...'), findsOneWidget);
  });

  testWidgets('PhaseIndicator shows Responding label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PhaseIndicator(phase: RespondingPhase()),
      ),
    ));

    expect(find.text('Responding...'), findsOneWidget);
  });

  testWidgets('ExecutionTimeline shows event count', (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(
      executionEvents: events,
      activities: Signal<List<ActivityRecord>>(const []),
      logger: testLogger(),
    );

    events.value = const ThinkingStarted();
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(_withStore(MaterialApp(
      home: Scaffold(
        body: ExecutionTimeline(
          roomId: 'r',
          messageId: 'm',
          tracker: tracker,
        ),
      ),
    )));

    expect(find.text('2 events'), findsOneWidget);

    tracker.dispose();
  });

  testWidgets('ExecutionThinkingBlock shows thinking label', (tester) async {
    final events = Signal<ExecutionEvent?>(null);
    final tracker = ExecutionTracker(
      executionEvents: events,
      activities: Signal<List<ActivityRecord>>(const []),
      logger: testLogger(),
    );

    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'Let me think about this');

    await tester.pumpWidget(_withStore(MaterialApp(
      home: Scaffold(
        body: ExecutionThinkingBlock(
          roomId: 'r',
          messageId: 'm',
          tracker: tracker,
        ),
      ),
    )));

    expect(find.text('Thinking'), findsOneWidget);

    tracker.dispose();
  });
}
