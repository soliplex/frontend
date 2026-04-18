import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_activity.dart';
import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/step_log.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  late Signal<ExecutionEvent?> events;
  late ExecutionTracker tracker;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    tracker = ExecutionTracker(executionEvents: events);
  });

  tearDown(() => tracker.dispose());

  testWidgets('returns empty widget when tracker has no steps', (tester) async {
    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('ThinkingStarted does not add a step', (tester) async {
    events.value = const ThinkingStarted();

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('shows singular label for one tool call', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('1 tool call'), findsOneWidget);
  });

  testWidgets('shows plural label for multiple tool calls', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallStarted(
      toolName: 'read_file',
      toolCallId: 'tc-2',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('2 tool calls'), findsOneWidget);
  });

  testWidgets('tap expands to show step details', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    expect(find.text('search'), findsNothing);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('search'), findsOneWidget);
  });

  testWidgets('tap again collapses step details', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('search'), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('search'), findsNothing);
  });

  testWidgets('active step shows CircularProgressIndicator', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('completed step shows check_circle icon', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'done',
    );

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('failed step shows error icon', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const RunFailed(error: 'oops');

    await tester.pumpWidget(wrap(StepLog(tracker: tracker)));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('duration formatted as seconds with 1 decimal', (tester) async {
    final step = ExecutionStep(
      label: 'search',
      status: StepStatus.completed,
      timestamp: const Duration(milliseconds: 1250),
    );

    final stepsSignal = Signal<List<ExecutionStep>>([step]);
    final fakeTracker = _FakeTracker(stepsSignal);

    await tester.pumpWidget(wrap(StepLog(tracker: fakeTracker)));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(find.text('1.3s'), findsOneWidget);
  });
}

/// Minimal tracker that exposes a pre-built steps signal for testing.
class _FakeTracker implements ExecutionTracker {
  _FakeTracker(this._stepsSignal);

  final Signal<List<ExecutionStep>> _stepsSignal;

  @override
  ReadonlySignal<List<ExecutionStep>> get steps => _stepsSignal;

  @override
  ReadonlySignal<List<ActivityEntry>> get activities =>
      Signal<List<ActivityEntry>>(const []);

  @override
  ReadonlySignal<Map<String, dynamic>> get aguiState =>
      Signal<Map<String, dynamic>>(const {});

  @override
  ReadonlySignal<List<ToolCallInfo>> get toolCalls =>
      Signal<List<ToolCallInfo>>(const []);

  @override
  ReadonlySignal<String?> get awaitingApprovalFor => Signal<String?>(null);

  @override
  bool get isFrozen => false;

  @override
  void freeze() {}

  @override
  void dispose() {}
}
