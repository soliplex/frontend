import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';

void main() {
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
}
