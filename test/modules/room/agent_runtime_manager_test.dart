import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';

import '../../helpers/fakes.dart';

void main() {
  late AgentRuntimeManager manager;

  setUp(() {
    manager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
  });

  tearDown(() async {
    await manager.dispose();
  });

  test('caches runtime by serverId', () {
    final connection = ServerConnection(
      serverId: 'server-1',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );

    final first = manager.getRuntime(connection);
    final second = manager.getRuntime(connection);
    expect(identical(first, second), isTrue);
  });

  test('creates separate runtimes for different servers', () {
    final conn1 = ServerConnection(
      serverId: 'server-1',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );
    final conn2 = ServerConnection(
      serverId: 'server-2',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );

    final rt1 = manager.getRuntime(conn1);
    final rt2 = manager.getRuntime(conn2);
    expect(identical(rt1, rt2), isFalse);
    expect(rt1.serverId, 'server-1');
    expect(rt2.serverId, 'server-2');
  });

  test('getRuntime throws after dispose', () async {
    await manager.dispose();
    final connection = ServerConnection(
      serverId: 'server-1',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );
    expect(() => manager.getRuntime(connection), throwsStateError);
  });

  test(
    'toolRegistryResolver returns the resolver passed at construction',
    () async {
      final registry = await manager.toolRegistryResolver('any-room');
      expect(registry, isA<ToolRegistry>());
    },
  );

  test('replaces runtime when connection changes for same serverId', () {
    final conn1 = ServerConnection(
      serverId: 'server-1',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );
    final conn2 = ServerConnection(
      serverId: 'server-1',
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );

    final rt1 = manager.getRuntime(conn1);
    final rt2 = manager.getRuntime(conn2);
    expect(identical(rt1, rt2), isFalse);
    expect(rt2.serverId, 'server-1');
  });
}
