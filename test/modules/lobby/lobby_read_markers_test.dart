import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LobbyReadMarkerStorage', () {
    test('defaults to empty when nothing is persisted', () async {
      expect(await LobbyReadMarkerStorage.load(), isEmpty);
    });

    test('round-trips markers, normalizing to UTC', () async {
      final markers = {
        (serverId: 'a', roomId: 'r1'): DateTime.utc(2026, 6, 1, 12),
        (serverId: 'b', roomId: 'r2'): DateTime.utc(2026, 1, 2, 3, 4),
      };
      await LobbyReadMarkerStorage.save(markers);

      final loaded = await LobbyReadMarkerStorage.load();
      expect(loaded, hasLength(2));
      expect(
          loaded[(serverId: 'a', roomId: 'r1')], DateTime.utc(2026, 6, 1, 12));
      expect(loaded[(serverId: 'b', roomId: 'r2')]!.isUtc, isTrue);
    });

    test('preserves ids that would collide under a naive composite key',
        () async {
      // Ids with separators must survive the JSON round-trip intact.
      final markers = {
        (serverId: 'a|b', roomId: 'r'): DateTime.utc(2026),
        (serverId: 'a', roomId: 'b|r'): DateTime.utc(2025),
      };
      await LobbyReadMarkerStorage.save(markers);

      final loaded = await LobbyReadMarkerStorage.load();
      expect(loaded, hasLength(2));
      expect(loaded[(serverId: 'a|b', roomId: 'r')], DateTime.utc(2026));
      expect(loaded[(serverId: 'a', roomId: 'b|r')], DateTime.utc(2025));
    });

    test('a corrupt payload loads as empty rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_read_markers': 'not json{'},
      );
      expect(await LobbyReadMarkerStorage.load(), isEmpty);
    });

    test('skips malformed entries but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_lobby_read_markers': '['
            '{"s":"a","r":"r1","t":"2026-06-01T00:00:00Z"},'
            '{"s":"a","r":"r2","t":"not-a-date"},'
            '{"s":"a","t":"2026-06-01T00:00:00Z"},'
            '"garbage"'
            ']',
      });
      final loaded = await LobbyReadMarkerStorage.load();
      expect(loaded, hasLength(1));
      expect(loaded[(serverId: 'a', roomId: 'r1')], DateTime.utc(2026, 6));
    });

    test('a non-list payload loads as empty', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_read_markers': '{"s":"a"}'},
      );
      expect(await LobbyReadMarkerStorage.load(), isEmpty);
    });
  });
}
