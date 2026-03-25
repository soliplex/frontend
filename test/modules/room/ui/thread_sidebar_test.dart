import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';

void main() {
  testWidgets('shows loading indicator when loading', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoading(),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows thread names when loaded', (tester) async {
    final threads = [
      ThreadInfo(
        id: 't-1',
        roomId: 'room-1',
        name: 'First thread',
        createdAt: DateTime(2026, 3, 1),
      ),
      ThreadInfo(
        id: 't-2',
        roomId: 'room-1',
        name: 'Second thread',
        createdAt: DateTime(2026, 3, 2),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: 't-1',
          onThreadSelected: (_) {},
          onBackToLobby: () {},
        ),
      ),
    ));

    expect(find.text('First thread'), findsOneWidget);
    expect(find.text('Second thread'), findsOneWidget);
  });

  testWidgets('calls onThreadSelected on tap', (tester) async {
    String? selectedId;
    final threads = [
      ThreadInfo(
        id: 't-1',
        roomId: 'room-1',
        name: 'Tappable thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: null,
          onThreadSelected: (id) => selectedId = id,
          onBackToLobby: () {},
        ),
      ),
    ));

    await tester.tap(find.text('Tappable thread'));
    expect(selectedId, 't-1');
  });

  testWidgets('shows back to lobby button', (tester) async {
    bool backCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () => backCalled = true,
        ),
      ),
    ));

    await tester.tap(find.text('Back to Lobby'));
    expect(backCalled, isTrue);
  });
}
