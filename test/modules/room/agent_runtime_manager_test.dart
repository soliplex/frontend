import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';

import '../../helpers/fakes.dart';

ServerConnection _connection(String serverId) => ServerConnection(
      serverId: serverId,
      api: FakeSoliplexApi(),
      agUiStreamClient: FakeAgUiStreamClient(),
    );

ServerEntry _entry(String serverId) => ServerEntry(
      serverId: serverId,
      alias: serverId,
      serverUrl: Uri.parse('https://$serverId.example.com'),
      auth: AuthSession(refreshService: FakeTokenRefreshService()),
      httpClient: FakeHttpClient(),
      connection: _connection(serverId),
    );

void main() {
  late AgentRuntimeManager manager;

  setUp(() {
    manager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      servers: emptyServers(),
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

  test('toolRegistryResolver returns the resolver passed at construction',
      () async {
    final registry = await manager.toolRegistryResolver('any-room');
    expect(registry, isA<ToolRegistry>());
  });

  test('evicts a runtime when its server is removed from the signal', () async {
    final servers = Signal<Map<String, ServerEntry>>({});
    final evicting = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      servers: servers,
    );
    addTearDown(() async {
      await evicting.dispose();
      servers.dispose();
    });

    final conn = _connection('server-1');
    servers.value = {'server-1': _entry('server-1')};
    final rt1 = evicting.getRuntime(conn);

    servers.value = {};

    // The stale runtime is actually disposed, not just dropped from the cache:
    // a disposed runtime rejects spawn. This catches a regression that evicts
    // the cache entry but skips disposal (the leak this eviction path fixes).
    await expectLater(
      rt1.spawn(roomId: 'r', prompt: 'p', threadId: 't'),
      throwsA(
        isA<StateError>()
            .having((e) => e.toString(), 'message', contains('disposed')),
      ),
    );
    // And re-requesting the same connection builds a fresh runtime.
    expect(identical(evicting.getRuntime(conn), rt1), isFalse);
  });

  test('keeps runtimes for servers that remain', () {
    final servers = Signal<Map<String, ServerEntry>>({});
    final evicting = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      servers: servers,
    );
    addTearDown(() async {
      await evicting.dispose();
      servers.dispose();
    });

    final conn1 = _connection('server-1');
    final conn2 = _connection('server-2');
    servers.value = {
      'server-1': _entry('server-1'),
      'server-2': _entry('server-2')
    };
    final rt1 = evicting.getRuntime(conn1);
    final rt2 = evicting.getRuntime(conn2);

    servers.value = {'server-2': _entry('server-2')};

    expect(identical(evicting.getRuntime(conn2), rt2), isTrue);
    expect(identical(evicting.getRuntime(conn1), rt1), isFalse);
  });

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
