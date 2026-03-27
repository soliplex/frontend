import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';
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

  setUp(() {
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
    registry = RunRegistry();
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
  });

  test('contributes room routes', () {
    final manager = _createManager();
    final contribution = roomModule(
      serverManager: manager,
      runtimeManager: runtimeManager,
      registry: registry,
    );
    final paths =
        contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, contains('/room/:serverAlias/:roomId'));
    expect(paths, contains('/room/:serverAlias/:roomId/:threadId'));
  });

  test('contributes no overrides in Slice A', () {
    final manager = _createManager();
    final contribution = roomModule(
      serverManager: manager,
      runtimeManager: runtimeManager,
      registry: registry,
    );
    expect(contribution.overrides, isEmpty);
  });
}
