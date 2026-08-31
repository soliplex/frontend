import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  late AgentRuntimeManager runtimeManager;
  late RunRegistry registry;
  late RoomAppModule module;

  setUp(() {
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      servers: emptyServers(),
    );
    registry = RunRegistry(servers: emptyServers());
    module = RoomAppModule(
      serverManager: _createManager(),
      runtimeManager: runtimeManager,
      registry: registry,
      roomReadMarkers: RoomReadMarkers(),
      serverReadMarkers: ServerReadMarkers(),
      appName: 'Soliplex',
    );
  });

  tearDown(() async {
    await module.onDispose();
  });

  test('contributes room routes', () {
    final contribution = module.build();
    final paths =
        contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, contains('/room/:serverAlias/:roomId'));
    expect(paths, contains('/room/:serverAlias/:roomId/thread/:threadId'));
  });

  test('contributes room info route before thread route', () {
    final contribution = module.build();
    final paths =
        contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, contains('/room/:serverAlias/:roomId/info'));

    final infoIndex = paths.indexOf('/room/:serverAlias/:roomId/info');
    final threadIndex =
        paths.indexOf('/room/:serverAlias/:roomId/thread/:threadId');
    expect(infoIndex, lessThan(threadIndex),
        reason:
            '/info must precede /:threadId to avoid eager parameter matching');
  });

  test('overrides messageExpansionsProvider so reads succeed', () {
    final contribution = module.build();

    // Resolving the provider through the module's overrides must not
    // throw — the default provider throws StateError.
    final container = ProviderContainer(overrides: contribution.overrides);
    addTearDown(container.dispose);
    expect(
      container.read(messageExpansionsProvider),
      isA<MessageExpansions>(),
    );
  });

  // The module is the only production site that supplies `appName` to the room
  // screen, and the compiler enforces only that it is supplied, not that the
  // module's own name is what reaches it. Every fixture in this repo is named
  // "Soliplex", so a hardcoded literal here is indistinguishable from a
  // correct forward in any build this repo can run — it surfaces only in a
  // fork, which is the audience the name exists for. Hence a distinctive name.
  testWidgets('forwards its app name to the disclaimer under the composer',
      (tester) async {
    final serverManager = _createManager();
    final forkModule = RoomAppModule(
      serverManager: serverManager,
      runtimeManager: runtimeManager,
      registry: registry,
      roomReadMarkers: RoomReadMarkers(),
      serverReadMarkers: ServerReadMarkers(),
      appName: 'Acme',
    );
    addTearDown(forkModule.onDispose);
    // requiresAuth: false makes the entry connected on arrival, which is what
    // the routes' requireConnectedServer redirect demands.
    serverManager.addServer(
      serverId: 'srv-1',
      serverUrl: Uri.parse('https://example.test'),
      requiresAuth: false,
      alias: 'srv',
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/room/srv/room-1',
          routes: forkModule.build().routes,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Acme is AI and can make mistakes.'), findsOneWidget);
  });
}
