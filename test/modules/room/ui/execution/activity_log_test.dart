import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/activity_log.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late Signal<ExecutionEvent?> events;
  late ExecutionTracker tracker;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    tracker = ExecutionTracker(executionEvents: events);
  });

  tearDown(() => tracker.dispose());

  testWidgets('returns empty widget when no activities', (tester) async {
    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('shows singular "activity" for one call', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('1 activity'), findsOneWidget);
  });

  testWidgets('shows plural "activities" for multiple calls', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}'},
      timestamp: 1,
    );
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_2',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'search', 'args': '{}'},
      timestamp: 2,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('2 activities'), findsOneWidget);
  });

  testWidgets('tap expands to show tool names', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'in_progress'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('ask'), findsNothing);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.text('ask'), findsOneWidget);
  });

  testWidgets('expanded row shows status label when present', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'done'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('shows spinner icon for in_progress status', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'in_progress'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows check icon for done status', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'done'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows error icon for failed status', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'failed'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.byIcon(Icons.error), findsOneWidget);
  });

  testWidgets('non-skill_tool_call activities are ignored', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'plan:1',
      activityType: 'plan',
      content: {'steps': 3},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('replace:true updates the existing row in place', (
    tester,
  ) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'in_progress'},
      timestamp: 1,
    );
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}', 'status': 'done'},
      timestamp: 2,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.text('1 activity'), findsOneWidget);
    expect(find.text('done'), findsOneWidget);
    expect(find.text('in_progress'), findsNothing);
  });

  testWidgets('tap again collapses the rows', (tester) async {
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'ask', 'args': '{}'},
      timestamp: 1,
    );

    await tester.pumpWidget(wrap(ActivityLog(tracker: tracker)));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.text('ask'), findsOneWidget);

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.text('ask'), findsNothing);
  });
}
