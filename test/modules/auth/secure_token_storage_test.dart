import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';

void main() {
  group('clearServersIfFreshInstall', () {
    late InMemoryServerStorage storage;

    setUp(() {
      storage = InMemoryServerStorage();
    });

    test('clears stored tokens on first launch', () async {
      SharedPreferences.setMockInitialValues({});

      await storage.save(
        'test-server',
        KnownServer(
          serverUrl: Uri.parse('https://api.example.com'),
          requiresAuth: false,
        ),
      );

      await clearServersIfFreshInstall(storage);

      final entries = await storage.loadAll();
      expect(entries, isEmpty);
    });

    test('preserves stored tokens on subsequent launches', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_has_launched': true,
      });

      await storage.save(
        'test-server',
        KnownServer(
          serverUrl: Uri.parse('https://api.example.com'),
          requiresAuth: false,
        ),
      );

      await clearServersIfFreshInstall(storage);

      final entries = await storage.loadAll();
      expect(entries, hasLength(1));
    });

    test('logs a storage failure without the stored data', () async {
      SharedPreferences.setMockInitialValues({});
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      await clearServersIfFreshInstall(
        FailingServerStorage(
          PlatformException(code: 'StorageError', message: 'refresh-secret'),
        ),
      );

      final record = sink.records.singleWhere(
        (r) => r.message == 'Failed to clear servers on fresh install',
      );
      expect(record.toString(), isNot(contains('refresh-secret')));
      expect(record.toString(), contains('StorageError'));
    });

    test('sets flag after clearing', () async {
      SharedPreferences.setMockInitialValues({});

      await clearServersIfFreshInstall(storage);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('soliplex_has_launched'), isTrue);
    });
  });
}
