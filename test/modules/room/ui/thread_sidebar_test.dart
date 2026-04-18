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
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
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
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
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
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
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
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
        ),
      ),
    ));

    await tester.tap(find.text('Lobby'));
    expect(backCalled, isTrue);
  });

  testWidgets('shows Debug Console button that fires callback',
      (tester) async {
    bool consoleCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () => consoleCalled = true,
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
        ),
      ),
    ));

    await tester.tap(find.text('Debug Console'));
    expect(consoleCalled, isTrue);
  });

  testWidgets('shows room name button that fires onRoomInfo', (tester) async {
    bool infoCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () => infoCalled = true,
          roomName: 'My Room',
          onRetryThreads: () async {},
        ),
      ),
    ));

    await tester.tap(find.text('My Room'));
    expect(infoCalled, isTrue);
  });

  testWidgets('wraps thread list with RefreshIndicator when callback provided',
      (tester) async {
    final threads = [
      ThreadInfo(
        id: 't-1',
        roomId: 'room-1',
        name: 'Thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
        ),
      ),
    ));

    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('no RefreshIndicator when onRetryThreads is null',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(const []),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
        ),
      ),
    ));

    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('rename callback propagates from ThreadTile', (tester) async {
    String? renamedId;
    final threads = [
      ThreadInfo(
        id: 't-1',
        roomId: 'room-1',
        name: 'Thread One',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
          onRenameThread: (id, name) => renamedId = id,
          onDeleteThread: (_) {},
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renamedId, 't-1');
  });

  testWidgets('delete callback propagates from ThreadTile', (tester) async {
    String? deletedId;
    final threads = [
      ThreadInfo(
        id: 't-1',
        roomId: 'room-1',
        name: 'Thread One',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ThreadSidebar(
          threadListStatus: ThreadsLoaded(threads),
          selectedThreadId: null,
          onThreadSelected: (_) {},
          onBackToLobby: () {},
          onCreateThread: () {},
          onDebugConsole: () {},
          onRoomInfo: () {},
          roomName: 'Test Room',
          onRetryThreads: () async {},
          onRenameThread: (_, __) {},
          onDeleteThread: (id) => deletedId = id,
        ),
      ),
    ));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deletedId, 't-1');
  });
}
