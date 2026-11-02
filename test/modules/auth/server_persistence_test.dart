import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/server_persistence.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

/// Fails every operation, as an unreadable or unwritable keychain would.
class _FailingStorage implements ServerStorage {
  @override
  Future<Map<String, PersistedServer>> loadAll() =>
      Future.error(StateError(''));

  @override
  Future<void> save(String serverId, PersistedServer data) =>
      Future.error(StateError(''));

  @override
  Future<void> delete(String serverId) => Future.error(StateError(''));
}

MemorySink _captureLogs() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return sink;
}

void main() {
  group('save', () {
    test('stores a signed-in server with its tokens', () async {
      final storage = InMemoryServerStorage();
      final persistence = ServerPersistence(storage);
      final entry = createTestServerEntry(auth: authInActiveSession());

      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      final stored = (await storage.loadAll())[entry.serverId];
      expect(stored, isA<AuthenticatedServer>());
      expect(stored!.alias, entry.alias);
    });

    test('keeps the tokens of an expired session', () async {
      final storage = InMemoryServerStorage();
      final persistence = ServerPersistence(storage);
      final auth = authInActiveSession()..markSessionExpired();
      final entry = createTestServerEntry(auth: auth);

      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      expect(
        (await storage.loadAll())[entry.serverId],
        isA<AuthenticatedServer>(),
      );
    });

    test('stores a signed-out server without tokens', () async {
      final storage = InMemoryServerStorage();
      final persistence = ServerPersistence(storage);
      final entry = createTestServerEntry();

      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      expect((await storage.loadAll())[entry.serverId], isA<KnownServer>());
    });

    test('a failed write is logged and the next one still runs', () async {
      final sink = _captureLogs();
      final persistence = ServerPersistence(_FailingStorage());
      final entry = createTestServerEntry();

      persistence
        ..save(entry)
        ..delete(entry.serverId);
      await persistence.whenPersisted(entry.serverId);

      expect(
        sink.records
            .where((r) => r.loggerName == 'soliplex.server_persistence')
            .map((r) => r.message),
        [
          'Failed to persist session for ${entry.serverId}',
          'Failed to delete stored session for ${entry.serverId}',
        ],
      );
    });
  });

  test('a delete queued after a save lands after it', () async {
    final storage = InMemoryServerStorage();
    final held = Completer<void>();
    storage.writesHeldUntil = held.future;
    final persistence = ServerPersistence(storage);
    final entry = createTestServerEntry();

    persistence
      ..save(entry)
      ..delete(entry.serverId);
    held.complete();
    await persistence.whenPersisted(entry.serverId);

    expect(await storage.loadAll(), isEmpty);
  });

  group('loadAll', () {
    test('returns the stored records', () async {
      final storage = InMemoryServerStorage();
      await storage.save(
        's1',
        KnownServer(serverUrl: Uri.parse('https://s1.example.com')),
      );

      final loaded = await ServerPersistence(storage).loadAll();

      expect(loaded!.keys, ['s1']);
    });

    test('is null, and logs, when the storage cannot be read', () async {
      final sink = _captureLogs();

      final loaded = await ServerPersistence(_FailingStorage()).loadAll();

      expect(loaded, isNull);
      expect(
        sink.records.map((r) => r.message),
        contains('Failed to load stored servers'),
      );
    });
  });

  test('whenPersisted completes at once for a server with nothing queued',
      () async {
    await expectLater(
      ServerPersistence(InMemoryServerStorage()).whenPersisted('none'),
      completes,
    );
  });
}
