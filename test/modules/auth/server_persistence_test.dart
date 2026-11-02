import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_persistence.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

/// A stored [AuthenticatedServer] holding [tokens].
Matcher _withTokens(AuthTokens tokens) =>
    isA<AuthenticatedServer>().having((s) => s.tokens, 'tokens', same(tokens));

AuthTokens _tokensOf(AuthSession auth) =>
    (auth.session.value as ActiveSession).tokens;

const _secret = 'refresh-secret';

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
      final auth = authInActiveSession();
      final entry = createTestServerEntry(auth: auth);

      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      expect(
        (await storage.loadAll())[entry.serverId],
        _withTokens(_tokensOf(auth)),
      );
    });

    test('keeps the tokens of an expired session', () async {
      final storage = InMemoryServerStorage();
      final persistence = ServerPersistence(storage);
      final auth = authInActiveSession();
      final tokens = _tokensOf(auth);
      auth.markSessionExpired();
      final entry = createTestServerEntry(auth: auth);

      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      expect((await storage.loadAll())[entry.serverId], _withTokens(tokens));
    });

    for (final (state, requiresAuth, auth)
        in <(String, bool, AuthSession? Function())>[
      ('no-auth', false, () => null),
      ('signed-out', true, () => null),
      ('signed-in', true, authInActiveSession),
    ]) {
      test('stores the details of a $state server', () async {
        final storage = InMemoryServerStorage();
        final persistence = ServerPersistence(storage);
        final entry = createTestServerEntry(
          auth: auth(),
          requiresAuth: requiresAuth,
          alias: 'research',
          name: 'Research',
          description: 'Team documents',
        );

        persistence.save(entry);
        await persistence.whenPersisted(entry.serverId);

        final stored = (await storage.loadAll())[entry.serverId]!;
        expect(stored.serverUrl, entry.serverUrl);
        expect(stored.alias, 'research');
        expect(stored.requiresAuth, requiresAuth);
        expect(stored.name, 'Research');
        expect(stored.description, 'Team documents');
      });
    }

    test('a failed operation is logged and the next one still runs', () async {
      final sink = _captureLogs();
      final persistence =
          ServerPersistence(FailingServerStorage(StateError('')));
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

  test('a save queued after a delete lands after it', () async {
    final storage = InMemoryServerStorage();
    final held = Completer<void>();
    storage.deletesHeldUntil = held.future;
    final persistence = ServerPersistence(storage);
    final entry = createTestServerEntry();

    persistence
      ..delete(entry.serverId)
      ..save(entry);
    held.complete();
    await persistence.whenPersisted(entry.serverId);
    // Without the queue, the save overtakes the held delete, and the delete
    // lands after whenPersisted completes; let it land before reading.
    await pumpEventQueue();

    expect((await storage.loadAll()).keys, [entry.serverId]);
  });

  group('loadAll', () {
    test('is null, and logs, when the storage cannot be read', () async {
      final sink = _captureLogs();

      final loaded =
          await ServerPersistence(FailingServerStorage(StateError('')))
              .loadAll();

      expect(loaded, isNull);
      expect(
        sink.records.map((r) => r.message),
        contains('Failed to load stored servers'),
      );
    });
  });

  for (final (label, failure, kept) in <(String, Object, List<String>)>[
    (
      'a parse failure',
      const FormatException('Unexpected character', '{"t":"$_secret"', 14),
      ['Unexpected character'],
    ),
    (
      'a platform failure with text details',
      PlatformException(
        code: 'StorageError',
        message: _secret,
        details: 'at read($_secret)',
      ),
      ['StorageError'],
    ),
    (
      'a platform failure with integer details',
      PlatformException(
          code: 'StorageError', message: _secret, details: -25308),
      ['StorageError', '-25308'],
    ),
  ]) {
    test('$label is logged without the stored data', () async {
      final sink = _captureLogs();
      final persistence = ServerPersistence(FailingServerStorage(failure));
      final entry = createTestServerEntry();

      await persistence.loadAll();
      persistence.save(entry);
      await persistence.whenPersisted(entry.serverId);

      final records = sink.records
          .where((r) => r.loggerName == 'soliplex.server_persistence');
      expect(records, hasLength(2));
      for (final record in records) {
        expect(record.toString(), isNot(contains(_secret)));
        for (final detail in kept) {
          expect(record.toString(), contains(detail));
        }
      }
    });
  }
}
