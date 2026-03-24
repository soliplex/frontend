import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/room_placeholder.dart';

import '../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  testWidgets('room route uses serverAlias path parameter', (tester) async {
    final manager = _createManager();
    manager.addServer(
      serverId: 'http://localhost:8000',
      serverUrl: Uri.parse('http://localhost:8000'),
      requiresAuth: false,
    );

    final contribution = roomPlaceholder(serverManager: manager);
    final router = GoRouter(
      initialLocation: '/room/localhost-8000/test-room',
      routes: contribution.routes,
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Room: test-room'), findsOneWidget);
    expect(
      find.textContaining('http://localhost:8000'),
      findsOneWidget,
    );
  });
}
