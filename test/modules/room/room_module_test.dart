import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/core/app_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';

import '../../helpers/fakes.dart';

class _NullContext implements AppModuleContext {
  @override
  T? module<T extends AppModule>() => null;
}

final _ctx = _NullContext();

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
    );
    registry = RunRegistry();
    module = RoomAppModule(
      serverManager: _createManager(),
      runtimeManager: runtimeManager,
      registry: registry,
    );
  });

  tearDown(() async {
    await module.onDispose();
  });

  test('contributes room routes', () {
    final contribution = module.build(_ctx);
    final paths =
        contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, contains('/room/:serverAlias/:roomId'));
    expect(paths, contains('/room/:serverAlias/:roomId/thread/:threadId'));
  });

  test('contributes room info route before thread route', () {
    final contribution = module.build(_ctx);
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

  test('contributes no overrides', () {
    final contribution = module.build(_ctx);
    expect(contribution.overrides, isEmpty);
  });
}
