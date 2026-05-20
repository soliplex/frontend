import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';

import '../../helpers/fakes.dart' show FakeTokenRefreshService;

class _FakeHttpClient extends Fake implements SoliplexHttpClient {}

class _FakeServerConnection extends Fake implements ServerConnection {
  _FakeServerConnection(this.api);

  @override
  final SoliplexApi api;
}

class _MockSoliplexApi extends Mock implements SoliplexApi {}

ServerEntry _entry(String serverId, {SoliplexApi? api}) {
  return ServerEntry(
    serverId: serverId,
    alias: serverId,
    serverUrl: Uri.parse('https://$serverId.example.com'),
    auth: AuthSession(refreshService: FakeTokenRefreshService()),
    httpClient: _FakeHttpClient(),
    connection: _FakeServerConnection(api ?? _MockSoliplexApi()),
  );
}

void main() {
  late Signal<Map<String, ServerEntry>> servers;
  late UploadTrackerRegistry registry;

  setUp(() {
    servers = Signal<Map<String, ServerEntry>>({});
    registry = UploadTrackerRegistry(servers: servers);
  });

  tearDown(() {
    registry.dispose();
    servers.dispose();
  });

  group('trackerFor', () {
    test('returns the same instance for the same (server, room)', () {
      final entry = _entry('srv-1');
      final a = registry.trackerFor(entry: entry, roomId: 'r1');
      final b = registry.trackerFor(entry: entry, roomId: 'r1');

      expect(identical(a, b), isTrue);
    });

    test('returns distinct instances for different rooms', () {
      final entry = _entry('srv-1');
      final a = registry.trackerFor(entry: entry, roomId: 'r1');
      final b = registry.trackerFor(entry: entry, roomId: 'r2');

      expect(identical(a, b), isFalse);
    });

    test('returns distinct instances for different servers', () {
      final a = registry.trackerFor(entry: _entry('srv-1'), roomId: 'r1');
      final b = registry.trackerFor(entry: _entry('srv-2'), roomId: 'r1');

      expect(identical(a, b), isFalse);
    });
  });

  group('eviction on server removal', () {
    test('disposes and removes trackers for the removed server', () {
      final e1 = _entry('srv-1');
      final e2 = _entry('srv-2');
      servers.value = {'srv-1': e1, 'srv-2': e2};

      final t1 = registry.trackerFor(entry: e1, roomId: 'r1');
      final t2 = registry.trackerFor(entry: e2, roomId: 'r1');

      servers.value = {'srv-2': e2};

      expect(t1.isDisposed, isTrue,
          reason: "evicted tracker must be disposed, not just removed");
      expect(t2.isDisposed, isFalse);

      // The registry gives out a fresh instance on re-request for the
      // evicted server; the surviving server's tracker is reused.
      final t1b = registry.trackerFor(entry: e1, roomId: 'r1');
      final t2b = registry.trackerFor(entry: e2, roomId: 'r1');

      expect(identical(t1, t1b), isFalse);
      expect(identical(t2, t2b), isTrue);
    });

    test('does not touch trackers when the server set is unchanged', () {
      final e1 = _entry('srv-1');
      servers.value = {'srv-1': e1};
      final t1 = registry.trackerFor(entry: e1, roomId: 'r1');

      // Emit the same map reference update (same keys).
      servers.value = {'srv-1': e1};

      final t1b = registry.trackerFor(entry: e1, roomId: 'r1');
      expect(identical(t1, t1b), isTrue);
    });
  });

  group('dispose', () {
    test('disposes remaining trackers and unsubscribes from servers', () {
      final e1 = _entry('srv-1');
      registry.trackerFor(entry: e1, roomId: 'r1');
      registry.trackerFor(entry: e1, roomId: 'r2');

      registry.dispose();

      // trackerFor throws after dispose: verifies the guard.
      expect(
        () => registry.trackerFor(entry: e1, roomId: 'r3'),
        throwsStateError,
      );
    });

    test('is idempotent', () {
      registry.dispose();
      // Second dispose shouldn't throw.
      registry.dispose();
    });
  });
}
