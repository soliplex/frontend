import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_client/soliplex_client.dart' show RagDocument;
import 'package:soliplex_frontend/src/core/removed_server_cleanup.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/document_selections.dart';
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
    DocumentSelections docs,
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
    final docs = DocumentSelections();
    final cleanup = RemovedServerCleanup(
      serverManager: manager,
      roomReadMarkers: room,
      serverReadMarkers: server,
      documentSelections: docs,
    );
    addTearDown(cleanup.dispose);
    return (
      manager: manager,
      room: room,
      server: server,
      docs: docs,
      cleanup: cleanup
    );
  }

  group('RemovedServerCleanup', () {
    test('clears the removed server for every user, keeping a survivor\'s',
        () async {
      final at = DateTime.utc(2026, 6, 1);
      final wired = wire();
      // Two users signed into s1 on this device: removal must clear both.
      wired.server.markRead(serverId: 's1', userId: 'alice', at: at);
      wired.server.markRead(serverId: 's1', userId: 'bob', at: at);
      wired.server.markRead(serverId: 's2', userId: 'alice', at: at);
      wired.room.markRead(serverId: 's1', userId: 'alice', roomId: 'r', at: at);
      wired.room.markRead(serverId: 's1', userId: 'bob', roomId: 'r', at: at);
      wired.room.markRead(serverId: 's2', userId: 'alice', roomId: 'r', at: at);
      await ThreadReadMarkerStorage.saveRoom(
          serverId: 's1', userId: 'u', roomId: 'r', markers: {'t': at});
      await ThreadReadMarkerStorage.saveRoom(
          serverId: 's2', userId: 'u', roomId: 'r', markers: {'t': at});

      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(wired.server.value.keys, {(serverId: 's2', userId: 'alice')});
      expect(wired.room.value.keys,
          {(serverId: 's2', userId: 'alice', roomId: 'r')});
      expect(
        await ThreadReadMarkerStorage.loadRoom(
            serverId: 's1', userId: 'u', roomId: 'r'),
        isEmpty,
      );
      expect(
        await ThreadReadMarkerStorage.loadRoom(
            serverId: 's2', userId: 'u', roomId: 'r'),
        {'t': at},
      );
    });

    test('clears the removed server\'s thread anchors and drafts', () async {
      final wired = wire();
      await ThreadAnchorStorage.saveRoom(
          serverId: 's1', userId: 'u', roomId: 'r', anchors: {'t': 'm1'});
      await ThreadAnchorStorage.saveRoom(
          serverId: 's2', userId: 'u', roomId: 'r', anchors: {'t': 'm2'});
      await ReturnToStorage.saveComposer(
        serverId: 's1',
        userId: 'u',
        roomId: 'r',
        unsentText: 's1 draft',
      );
      await ReturnToStorage.saveComposer(
        serverId: 's2',
        userId: 'u',
        roomId: 'r',
        unsentText: 's2 draft',
      );

      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(
        await ThreadAnchorStorage.loadRoom(
            serverId: 's1', userId: 'u', roomId: 'r'),
        isEmpty,
      );
      expect(
        await ThreadAnchorStorage.loadRoom(
            serverId: 's2', userId: 'u', roomId: 'r'),
        {'t': 'm2'},
      );
      expect(
        await ReturnToStorage.loadComposer(
            serverId: 's1', userId: 'u', roomId: 'r'),
        isNull,
      );
      expect(
        await ReturnToStorage.loadComposer(
            serverId: 's2', userId: 'u', roomId: 'r'),
        's2 draft',
      );
    });

    test('clears the removed server\'s document selections, keeping others\'',
        () async {
      const doc = RagDocument(id: 'd1', title: 'Doc');
      final wired = wire();
      wired.docs.set(serverId: 's1', roomId: 'r', threadId: 't', docs: {doc});
      wired.docs.set(serverId: 's2', roomId: 'r', threadId: 't', docs: {doc});

      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(
          wired.docs.get(serverId: 's1', roomId: 'r', threadId: 't'), isEmpty);
      expect(wired.docs.get(serverId: 's2', roomId: 'r', threadId: 't'), {doc});
    });

    // A signal empty-out is not a removal: ServerManager.dispose() empties the
    // servers signal on shell teardown, but that state is meant to survive to
    // the next launch. The cleanup keys off the removeServer event, so a bare
    // dispose must not wipe anything.
    test('ServerManager.dispose does not clear device-local state', () async {
      final at = DateTime.utc(2026, 6, 1);
      final wired = wire();
      wired.server.markRead(serverId: 's1', userId: 'u', at: at);
      wired.room.markRead(serverId: 's1', userId: 'u', roomId: 'r', at: at);

      wired.manager.dispose();
      await pumpEventQueue();

      expect(wired.server.value.containsKey((serverId: 's1', userId: 'u')),
          isTrue);
      expect(
        wired.room.value
            .containsKey((serverId: 's1', userId: 'u', roomId: 'r')),
        isTrue,
      );
    });

    // dispose() unsubscribes from the removal event, so a removal after dispose
    // is a no-op. The owning module disposes the cleanup on teardown; this pins
    // that a disposed cleanup no longer reacts.
    test('a disposed cleanup ignores later server removals', () async {
      final at = DateTime.utc(2026, 6, 1);
      final wired = wire();
      wired.server.markRead(serverId: 's1', userId: 'u', at: at);
      wired.room.markRead(serverId: 's1', userId: 'u', roomId: 'r', at: at);

      wired.cleanup.dispose();
      wired.manager.removeServer('s1');
      await pumpEventQueue();

      expect(wired.server.value.containsKey((serverId: 's1', userId: 'u')),
          isTrue);
      expect(
        wired.room.value
            .containsKey((serverId: 's1', userId: 'u', roomId: 'r')),
        isTrue,
      );
    });
  });
}
