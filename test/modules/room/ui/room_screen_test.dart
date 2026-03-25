import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';

void main() {
  late FakeSoliplexApi api;
  late ServerEntry entry;

  setUp(() {
    api = FakeSoliplexApi();
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];
    api.nextThreadHistory = ThreadHistory(messages: const []);
    entry = createTestServerEntry(api: api);
  });

  testWidgets('wide layout shows thread sidebar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(
      home: RoomScreen(
        serverEntry: entry,
        roomId: 'room-1',
        threadId: null,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Test thread'), findsOneWidget);
  });
}
