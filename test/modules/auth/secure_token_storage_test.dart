import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';

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
      SharedPreferences.setMockInitialValues({'soliplex_has_launched': true});

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

    test('sets flag after clearing', () async {
      SharedPreferences.setMockInitialValues({});

      await clearServersIfFreshInstall(storage);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('soliplex_has_launched'), isTrue);
    });
  });
}
