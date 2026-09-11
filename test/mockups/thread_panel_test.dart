import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/mockups/chat/context_gauge.dart';
import 'package:soliplex_frontend/src/mockups/chat/thread_panel/panel_sample_data.dart';
import 'package:soliplex_frontend/src/mockups/chat/thread_panel/panel_state.dart';
import 'package:soliplex_frontend/src/mockups/chat/thread_panel/thread_panel.dart';

void main() {
  late ThreadPanelState state;

  setUp(() => state = samplePanelState());
  tearDown(() => state.dispose());

  Future<void> pump(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s3),
            child: Align(
              alignment: Alignment.topRight,
              child: ThreadPanel(state: state),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the databases segment and collapses to a handle',
      (tester) async {
    await pump(tester);
    expect(find.text('Databases'), findsOneWidget);
    expect(find.text('Retrieval papers'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Context usage'), findsOneWidget);
    // Skills content stays closed until asked for.
    expect(find.text('Auto-load basic skills'), findsNothing);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    expect(find.text('Databases'), findsNothing);
    expect(find.byTooltip('Open thread panel'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // connected databases

    await tester.tap(find.byTooltip('Open thread panel'));
    await tester.pumpAndSettle();
    expect(find.text('Databases'), findsOneWidget);
  });

  testWidgets('connecting a database updates its badge and the context ring',
      (tester) async {
    await pump(tester);
    final before = state.contextUsage.tokens;

    // The action only shows on hover; before that, the row ignores it.
    final row = find.text('Benchmark results');
    await tester.tap(find.text('Connect').first, warnIfMissed: false);
    await tester.pump();
    expect(state.databases.firstWhere((d) => d.id == 'benchmarks').status,
        DbStatus.available,
        reason: 'hidden action must not react');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pumpAndSettle();
    // The two connected rows come first, so the first Connect button is
    // 'Benchmark results'.
    await tester.tap(find.text('Connect').first);
    await tester.pump();
    expect(state.databases.firstWhere((d) => d.id == 'benchmarks').status,
        DbStatus.connecting);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(state.databases.firstWhere((d) => d.id == 'benchmarks').status,
        DbStatus.connected);
    expect(state.contextUsage.tokens, greaterThan(before));
    expect(find.text('3 of 18 connected'), findsOneWidget);
  });

  testWidgets('a row expands to its description', (tester) async {
    await pump(tester);
    expect(find.textContaining('Forty-one papers'), findsNothing);
    await tester.tap(find.text('Retrieval papers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Forty-one papers'), findsOneWidget);
  });

  testWidgets(
      'skills: the switch drops basic skills, Load adds an advanced one',
      (tester) async {
    await pump(tester);
    // Close Databases so the Skills segment gets the height to show its list.
    await tester.tap(find.text('Databases'));
    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    expect(state.loadedSkills.length, 3);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(state.loadedSkills, isEmpty);
    expect(find.textContaining('Nothing in context'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Load').first, 50);
    // Expanding the row is the touch route to the action.
    await tester.tap(find.text('Methodology critique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load').first);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(state.loadedSkills.map((s) => s.name), ['Methodology critique']);
    expect(find.text('Unload'), findsOneWidget);
  });

  testWidgets('generating a handoff shows the summary with its actions',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Databases'));
    await tester.tap(find.text('Context usage'));
    await tester.pumpAndSettle();
    expect(find.byType(ContextRing), findsOneWidget);
    expect(find.text('41,200 of 128,000 tokens'), findsOneWidget);

    await tester.tap(find.text('Generate handoff'));
    await tester.pump();
    expect(state.handoffStatus, HandoffStatus.generating);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Handoff'), findsOneWidget);
    expect(find.textContaining('Thread so far'), findsOneWidget);

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Generate handoff'), findsOneWidget);
  });

  testWidgets('workspace: recipients, an embedded document, and send',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('EL'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);

    await tester.tap(find.byTooltip('Add recipients'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Priya Natarajan'));
    await tester.pumpAndSettle();
    expect(state.recipients.length, 3);
    // The checklist stays open for more picks; a tap outside dismisses it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Embed a document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A Survey of Neural Retrieval').last);
    await tester.pumpAndSettle();
    expect(state.embeddedDocuments.length, 1);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Retrieval notes');
    await tester.pumpAndSettle();
    expect(state.recipients.length, 3, reason: 'escape must not clear picks');
    final send = tester
        .widget<SoliplexButton>(find.widgetWithText(SoliplexButton, 'Send'));
    expect(send.onPressed, isNotNull,
        reason: 'title typed and recipients picked');
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(state.sentCount, 1);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent to Erik Lindqvist'), findsOneWidget);
    expect(state.recipients, isEmpty);
    expect(state.sentCount, 1);
  });

  testWidgets('collapsing and reopening keeps what was open, scrolled, typed',
      (tester) async {
    await pump(tester);
    // Open Skills too, expand a database row, scroll the database list.
    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retrieval papers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Forty-one papers'), findsOneWidget);
    await tester.drag(find.text('Retrieval papers'), const Offset(0, -60));
    await tester.pumpAndSettle();
    final scrolled = tester.getTopLeft(find.text('Retrieval papers')).dy;
    // Type a note on the other tab.
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Draft title');
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open thread panel'), findsOneWidget);
    await tester.tap(find.byTooltip('Open thread panel'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-load basic skills'), findsOneWidget);
    expect(find.textContaining('Forty-one papers'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Retrieval papers')).dy, scrolled);
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Draft title'), findsOneWidget);
  });
}
