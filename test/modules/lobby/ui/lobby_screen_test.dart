import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildApp(ServerManager manager) {
  final router = GoRouter(
    initialLocation: '/lobby',
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, __) => LobbyScreen(serverManager: manager),
      ),
      GoRoute(
        path: '/servers',
        builder: (_, __) => const Scaffold(body: Text('Servers')),
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('LobbyScreen', () {
    testWidgets('shows sidebar on wide viewport with Add Server visible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // No hamburger menu icon in wide layout
      expect(find.byIcon(Icons.menu), findsNothing);

      // Sidebar Add Server button is directly visible (no Drawer wrapping it)
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Add Server'), findsWidgets);
    });

    testWidgets(
        'uses drawer on narrow viewport — hamburger opens drawer with Add Server',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Hamburger icon present in narrow layout
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // Drawer not yet open
      expect(find.byType(Drawer), findsNothing);

      // Open the drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer is now open and contains the sidebar with Add Server
      expect(find.byType(Drawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Add Server'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows empty state CTA when no servers connected',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Empty state: prominent Add Server CTA in the room content area
      expect(find.text('No servers connected'), findsOneWidget);
    });
  });
}
