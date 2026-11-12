import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/mockups/chat/static_backend.dart';
import 'package:soliplex_frontend/src/mockups/datasets/ui/threads/threads_view.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/lobby/global_threads_state.dart';
import 'package:soliplex_frontend/src/stores/labels_state.dart';

import '../helpers/test_server_entry.dart';

void main() {
  Future<void> pumpSignedOut(WidgetTester tester, {AuthSession? auth}) async {
    final entry = createTestServerEntry(requiresAuth: true, auth: auth);
    final threads = GlobalThreadsState(entryResolver: (_) => entry)
      ..setServer(entry.serverId);
    final labels = LabelsState(entryResolver: (_) => entry);
    addTearDown(threads.dispose);
    addTearDown(labels.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ThreadsView(
            state: threads,
            labels: labels,
            api: StaticSoliplexApi(rooms: [], threads: {}, histories: {}),
            roomNames: const {},
            roomlessId: 'conversations',
            onThreadTap: (_, __) {},
            onThreadAction: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-out server asks the user to sign in, not retry',
      (tester) async {
    await pumpSignedOut(tester);

    expect(find.text('Signed out'), findsOneWidget);
    expect(
        find.text('Sign in to view threads on this server.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('an expired session says so', (tester) async {
    final auth = authInActiveSession()..markSessionExpired();
    await pumpSignedOut(tester, auth: auth);

    expect(find.text('Session expired'), findsOneWidget);
    expect(
      find.text('Sign in again to view threads on this server.'),
      findsOneWidget,
    );
  });
}
