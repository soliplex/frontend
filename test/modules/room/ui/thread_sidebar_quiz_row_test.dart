import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';

void main() {
  final emptyRunning = Signal(<String>{}).readonly();

  Widget buildSidebar({
    Map<String, String> quizzes = const {},
    void Function(String)? onQuizTapped,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          runningThreadIds: emptyRunning,
          quizzes: quizzes,
          onQuizTapped: onQuizTapped,
        ),
      ),
    );
  }

  testWidgets('shows quiz row when quizzes present', (tester) async {
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Intro Quiz'},
    ));
    expect(find.text('Intro Quiz'), findsOneWidget);
  });

  testWidgets('hides quiz row when no quizzes', (tester) async {
    await tester.pumpWidget(buildSidebar());
    expect(find.byIcon(Icons.quiz), findsNothing);
  });

  testWidgets('fires onQuizTapped for single quiz', (tester) async {
    String? tapped;
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Intro Quiz'},
      onQuizTapped: (id) => tapped = id,
    ));
    await tester.tap(find.text('Intro Quiz'));
    expect(tapped, 'q1');
  });

  testWidgets('single quiz button disabled when onQuizTapped is null',
      (tester) async {
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Intro Quiz'},
      // onQuizTapped intentionally omitted (null)
    ));
    // Walk up from the label text to find the enclosing TextButton.
    final textElement = find.text('Intro Quiz').evaluate().single;
    TextButton? quizButton;
    textElement.visitAncestorElements((element) {
      if (element.widget is TextButton) {
        quizButton = element.widget as TextButton;
        return false;
      }
      return true;
    });
    expect(quizButton, isNotNull);
    expect(quizButton!.onPressed, isNull);
  });

  testWidgets('shows expandable header for multiple quizzes', (tester) async {
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Quiz A', 'q2': 'Quiz B'},
    ));
    expect(find.text('Quizzes (2)'), findsOneWidget);
    // Individual quizzes hidden until expanded
    expect(find.text('Quiz A'), findsNothing);
  });

  testWidgets('expands to show individual quizzes on tap', (tester) async {
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Quiz A', 'q2': 'Quiz B'},
    ));
    await tester.tap(find.text('Quizzes (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz A'), findsOneWidget);
    expect(find.text('Quiz B'), findsOneWidget);
  });

  testWidgets('collapses expanded quizzes on second tap', (tester) async {
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Quiz A', 'q2': 'Quiz B'},
    ));
    // Expand
    await tester.tap(find.text('Quizzes (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz A'), findsOneWidget);

    // Collapse
    await tester.tap(find.text('Quizzes (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Quiz A'), findsNothing);
  });

  testWidgets('fires onQuizTapped for expanded quiz', (tester) async {
    String? tapped;
    await tester.pumpWidget(buildSidebar(
      quizzes: {'q1': 'Quiz A', 'q2': 'Quiz B'},
      onQuizTapped: (id) => tapped = id,
    ));
    await tester.tap(find.text('Quizzes (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiz B'));
    expect(tapped, 'q2');
  });
}
