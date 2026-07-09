import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';
import 'package:soliplex_frontend/src/modules/room/user_switch_teardown.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

const _key = (serverId: 's1', roomId: 'room', threadId: 'thread');
const _doc = RagDocument(id: 'd1', title: 'Doc');

void _login(ServerEntry entry, String sub) {
  entry.auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
      clientId: 'test-client',
    ),
    tokens: AuthTokens(
      accessToken: testAccessToken(sub: sub),
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
}

typedef _Wired = ({
  ServerManager manager,
  ServerEntry entry,
  AgentRuntimeManager runtimeManager,
  RunRegistry registry,
  UploadTrackerRegistry uploadRegistry,
  DocumentSelections docs,
});

void main() {
  // Builds a server signed in as [initialSub], with the four managers wired to
  // the server signal but NOT yet populated, and NO coordinator yet — so a test
  // controls exactly when the coordinator first sees the identity.
  _Wired wire({String initialSub = 'alice'}) {
    final manager = ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );
    manager.addServer(
      serverId: 's1',
      serverUrl: Uri.parse('http://s1.test'),
    );
    final entry = manager.servers.value['s1']!;
    _login(entry, initialSub);

    final runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      servers: manager.servers,
    );
    final registry = RunRegistry(servers: manager.servers);
    final uploadRegistry = UploadTrackerRegistry(servers: manager.servers);
    final docs = DocumentSelections();

    addTearDown(() async {
      registry.dispose();
      uploadRegistry.dispose();
      await runtimeManager.dispose();
      manager.dispose();
    });

    return (
      manager: manager,
      entry: entry,
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
      docs: docs,
    );
  }

  UserSwitchTeardown coordinator(_Wired w) {
    final teardown = UserSwitchTeardown(
      servers: w.manager.servers,
      runtimeManager: w.runtimeManager,
      registry: w.registry,
      uploadRegistry: w.uploadRegistry,
      documentSelections: w.docs,
    );
    addTearDown(teardown.dispose);
    return teardown;
  }

  // Fills all four managers with state attributable to the current user.
  ({AgentRuntime runtime, UploadTracker tracker}) populate(_Wired w) {
    final runtime = w.runtimeManager.getRuntime(w.entry.connection);
    w.registry.register(_key, ManualAgentSession(_key));
    final tracker = w.uploadRegistry.trackerFor(entry: w.entry, roomId: 'room');
    w.docs.set('room', 'thread', {_doc});
    return (runtime: runtime, tracker: tracker);
  }

  void expectEvicted(_Wired w, AgentRuntime runtime, UploadTracker tracker) {
    expect(identical(w.runtimeManager.getRuntime(w.entry.connection), runtime),
        isFalse,
        reason: 'runtime should be evicted and rebuilt');
    expect(w.registry.activeSession(_key), isNull,
        reason: 'run should be evicted');
    expect(
      identical(
          w.uploadRegistry.trackerFor(entry: w.entry, roomId: 'room'), tracker),
      isFalse,
      reason: 'upload tracker should be evicted and rebuilt',
    );
    expect(w.docs.get('room', 'thread'), isEmpty,
        reason: 'document selections should be cleared');
  }

  void expectRetained(_Wired w, AgentRuntime runtime, UploadTracker tracker) {
    expect(identical(w.runtimeManager.getRuntime(w.entry.connection), runtime),
        isTrue,
        reason: 'runtime should be retained');
    expect(w.registry.activeSession(_key), isNotNull,
        reason: 'run should be retained');
    expect(
      identical(
          w.uploadRegistry.trackerFor(entry: w.entry, roomId: 'room'), tracker),
      isTrue,
      reason: 'upload tracker should be retained',
    );
    expect(w.docs.get('room', 'thread'), isNotEmpty,
        reason: 'document selections should be retained');
  }

  group('UserSwitchTeardown', () {
    test('a different user signing in evicts the prior user\'s state', () {
      final w = wire(initialSub: 'alice');
      coordinator(w);
      final captured = populate(w);

      w.entry.auth.logout();
      _login(w.entry, 'bob');

      expectEvicted(w, captured.runtime, captured.tracker);
    });

    test('a same-user token refresh evicts nothing', () {
      final w = wire(initialSub: 'alice');
      coordinator(w);
      final captured = populate(w);

      // A refresh swaps the session for the same identity.
      _login(w.entry, 'alice');

      expectRetained(w, captured.runtime, captured.tracker);
    });

    test('first sight of an already-signed-in user does not evict', () {
      final w = wire(initialSub: 'alice');
      final captured = populate(w);

      // Coordinator constructed AFTER the user already has live state, as on a
      // cold boot where restoreServers signed the user in before wiring.
      coordinator(w);

      expectRetained(w, captured.runtime, captured.tracker);
    });

    test('a switch on one server leaves another server\'s state intact', () {
      final w = wire(initialSub: 'alice');
      w.manager.addServer(
        serverId: 's2',
        serverUrl: Uri.parse('http://s2.test'),
      );
      final other = w.manager.servers.value['s2']!;
      _login(other, 'carol');

      coordinator(w);

      // Live state on the untouched server.
      final otherRuntime = w.runtimeManager.getRuntime(other.connection);
      const otherKey = (serverId: 's2', roomId: 'room', threadId: 'thread');
      w.registry.register(otherKey, ManualAgentSession(otherKey));
      final otherTracker =
          w.uploadRegistry.trackerFor(entry: other, roomId: 'room');

      final captured = populate(w);
      w.entry.auth.logout();
      _login(w.entry, 'bob');

      expectEvicted(w, captured.runtime, captured.tracker);
      // The three server-keyed registries isolate per server; only s1 is torn
      // down. (DocumentSelections has no server dimension and is cleared
      // wholesale by design.)
      expect(
        identical(w.runtimeManager.getRuntime(other.connection), otherRuntime),
        isTrue,
        reason: "other server's runtime should survive",
      );
      expect(w.registry.activeSession(otherKey), isNotNull,
          reason: "other server's run should survive");
      expect(
        identical(w.uploadRegistry.trackerFor(entry: other, roomId: 'room'),
            otherTracker),
        isTrue,
        reason: "other server's upload tracker should survive",
      );
    });

    test('expiry then a different user signing in evicts the prior state', () {
      final w = wire(initialSub: 'alice');
      coordinator(w);
      final captured = populate(w);

      // Session expires without an explicit logout.
      w.entry.auth.markSessionExpired();
      expectRetained(w, captured.runtime, captured.tracker);

      _login(w.entry, 'bob');
      expectEvicted(w, captured.runtime, captured.tracker);
    });
  });
}
