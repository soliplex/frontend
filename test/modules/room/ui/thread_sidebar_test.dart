import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_sidebar.dart';

void main() {
  testWidgets('shows loading indicator when loading', (tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoading(),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () {},
          onRetryThreads: () {},
        ),
      ),
    )));
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

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: 't-1',
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () {},
          onRetryThreads: () {},
        ),
      ),
    )));

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

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: null,
          onThreadSelected: (id) => selectedId = id,
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () {},
          onRetryThreads: () {},
        ),
      ),
    )));

    await tester.tap(find.text('Tappable thread'));
    expect(selectedId, 't-1');
  });

  testWidgets('shows back to lobby button', (tester) async {
    bool backCalled = false;

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () => backCalled = true,
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () {},
          onRetryThreads: () {},
        ),
      ),
    )));

    await tester.tap(find.text('Lobby'));
    expect(backCalled, isTrue);
  });

  testWidgets('shows Network Inspector button that fires callback',
      (tester) async {
    bool inspectorCalled = false;

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () => inspectorCalled = true,
          onRoomInfo: () {},
          onRetryThreads: () {},
        ),
      ),
    )));

    await tester.tap(find.text('Network Inspector'));
    expect(inspectorCalled, isTrue);
  });

  testWidgets('shows Room Info button that fires callback', (tester) async {
    bool infoCalled = false;

    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onNetworkInspector: () {},
          onRoomInfo: () => infoCalled = true,
          onRetryThreads: () {},
        ),
      ),
    )));

    await tester.tap(find.text('Room Info'));
    expect(infoCalled, isTrue);
  });
}
