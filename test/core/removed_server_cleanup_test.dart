import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/core/removed_server_cleanup.dart';
import 'package:soliplex_frontend/src/core/shell_config.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_anchor_storage.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart';

import '../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({
    ServerManager manager,
    RoomReadMarkers room,
    ServerReadMarkers server,
    RemovedServerCleanup cleanup,
  }) wire() {
    final manager = _createManager();
    manager.addServer(
      serverId: 's1',
      serverUrl: Uri.parse('http://s1.test'),
      requiresAuth: false,
    );
    manager.addServer(
      serverId: 's2',
      serverUrl: Uri.parse('http://s2.test'),
      requiresAuth: false,
    );
    final room = RoomReadMarkers();
    final server = ServerReadMarkers();
    final cleanup = RemovedServerCleanup(
      servers: manager.servers,
      roomReadMarkers: room,
      serverReadMarkers: server,
    );
    addTearDown(cleanup.dispose);
    return (manager: manager, room: room, server: server, cleanup: cleanup);
  }

  group('RemovedServerCleanup', () {
    test('clears the removed server\'s read markers, keeping a survivor\'s',
        () async {
      final at = DateTime.utc(2026, 6, 1);
      final wired = wire();
      wired.server.markRead('s1', at);
      wired.server.markRead('s2', at);
      wired.room.markRead((serverId: 's1', roomId: 'r'), at);
      wired.room.markRead((serverId: 's2', roomId: 'r'), at);
      await ThreadReadMarkerStorage.save({
        (serverId: 's1', roomId: 'r', threadId: 't'): at,
        (serverId: 's2', roomId: 'r', threadId: 't'): at,
      });

      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(wired.server.value.containsKey('s1'), isFalse);
      expect(wired.server.value.containsKey('s2'), isTrue);
      expect(
        wired.room.value.containsKey((serverId: 's1', roomId: 'r')),
        isFalse,
      );
      expect(
        wired.room.value.containsKey((serverId: 's2', roomId: 'r')),
        isTrue,
      );
      final threads = await ThreadReadMarkerStorage.load();
      expect(
        threads.containsKey((serverId: 's1', roomId: 'r', threadId: 't')),
        isFalse,
      );
      expect(
        threads.containsKey((serverId: 's2', roomId: 'r', threadId: 't')),
        isTrue,
      );
    });

    test('clears the removed server\'s thread anchors and drafts', () async {
      final wired = wire();
      await ThreadAnchorStorage.save({
        (serverId: 's1', roomId: 'r', threadId: 't'): 'm1',
        (serverId: 's2', roomId: 'r', threadId: 't'): 'm2',
      });
      await ReturnToStorage.saveComposer(
        serverId: 's1',
        roomId: 'r',
        unsentText: 's1 draft',
      );
      await ReturnToStorage.saveComposer(
        serverId: 's2',
        roomId: 'r',
        unsentText: 's2 draft',
      );

      wired.manager.removeServer('s1');
      await pumpEventQueue();

      final anchors = await ThreadAnchorStorage.load();
      expect(
        anchors.containsKey((serverId: 's1', roomId: 'r', threadId: 't')),
        isFalse,
      );
      expect(
        anchors.containsKey((serverId: 's2', roomId: 'r', threadId: 't')),
        isTrue,
      );
      expect(
        await ReturnToStorage.loadComposer(serverId: 's1', roomId: 'r'),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(serverId: 's2', roomId: 'r'),
        's2 draft',
      );
    });

    // Disposing must stop the cleanup observing. On shell teardown
    // ServerManager empties the servers signal, and a still-subscribed cleanup
    // would read that as a mass removal and wipe every server's state — even
    // though teardown keeps stored sessions for the next launch. Its owning
    // module disposes it before that empty-out; this pins the guard that makes
    // that ordering safe.
    test('a disposed cleanup ignores later server removals', () async {
      final at = DateTime.utc(2026, 6, 1);
      final wired = wire();
      wired.server.markRead('s1', at);
      wired.room.markRead((serverId: 's1', roomId: 'r'), at);

      wired.cleanup.dispose();
      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(wired.server.value.containsKey('s1'), isTrue);
      expect(
        wired.room.value.containsKey((serverId: 's1', roomId: 'r')),
        isTrue,
      );
    });
  });

  // Guards that RoomAppModule.onDispose stops the cleanup before ServerManager
  // empties the servers signal. If onDispose ever drops the
  // _removedServerCleanup.dispose() call, the still-subscribed cleanup reads the
  // teardown empty-out as a mass removal and wipes every server's state; this
  // drives the real modules through the real ShellConfig teardown to catch that.
  // It does not pin the production registration order itself (this list is built
  // here, not read from the flavor) — that ordering is a cross-module contract.
  group('teardown ordering (shell composition)', () {
    final at = DateTime.utc(2026, 6, 1);
    const roomKey = (serverId: 's1', roomId: 'r');
    const threadKey = (serverId: 's1', roomId: 'r', threadId: 't');

    test('teardown leaves a surviving session\'s device-local state intact',
        () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 's1',
        serverUrl: Uri.parse('http://s1.test'),
        requiresAuth: false,
      );
      final room = RoomReadMarkers();
      final server = ServerReadMarkers();
      final runtimeManager = AgentRuntimeManager(
        platform: TestPlatformConstraints(),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        logger: testLogger(),
        servers: manager.servers,
      );
      final registry = RunRegistry(servers: manager.servers);
      final authMod = AuthAppModule(
        serverManager: manager,
        probeClient: FakeHttpClient(),
        authFlow: FakeAuthFlow(),
        appName: 'Soliplex',
        inactivityLogoutFlags: InMemoryInactivityLogoutFlagStorage(),
      );
      // RoomAppModule builds its own RemovedServerCleanup over these markers.
      final roomMod = RoomAppModule(
        serverManager: manager,
        runtimeManager: runtimeManager,
        registry: registry,
        roomReadMarkers: room,
        serverReadMarkers: server,
        appName: 'Soliplex',
      );
      // Auth before room, matching the flavor: reverse-order teardown disposes
      // room (stopping the cleanup) before auth empties the signal.
      final config = await ShellConfig.fromModules(
        appName: 'Soliplex',
        lightTheme: ThemeData(),
        modules: [authMod, roomMod],
      );

      server.markRead('s1', at);
      room.markRead(roomKey, at);
      await ThreadReadMarkerStorage.save({threadKey: at});
      await ThreadAnchorStorage.save({threadKey: 'm1'});
      await ReturnToStorage.saveComposer(
        serverId: 's1',
        roomId: 'r',
        unsentText: 'draft',
      );

      await config.dispose?.call();
      await pumpEventQueue();

      expect(server.value.containsKey('s1'), isTrue);
      expect(room.value.containsKey(roomKey), isTrue);
      expect(
        (await ThreadReadMarkerStorage.load()).containsKey(threadKey),
        isTrue,
      );
      expect((await ThreadAnchorStorage.load()).containsKey(threadKey), isTrue);
      expect(
        await ReturnToStorage.loadComposer(serverId: 's1', roomId: 'r'),
        'draft',
      );
    });
  });
}
