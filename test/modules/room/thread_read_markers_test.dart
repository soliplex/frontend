import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/room/thread_read_markers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ThreadReadMarkerStorage', () {
    test('defaults to empty when nothing is persisted', () async {
      expect(await ThreadReadMarkerStorage.load(), isEmpty);
    });

    test('round-trips markers, normalizing to UTC', () async {
      final markers = {
        (serverId: 'a', roomId: 'r1', threadId: 't1'):
            DateTime.utc(2026, 6, 1, 12),
        (serverId: 'b', roomId: 'r2', threadId: 't2'):
            DateTime.utc(2026, 1, 2, 3, 4),
      };
      await ThreadReadMarkerStorage.save(markers);

      final loaded = await ThreadReadMarkerStorage.load();
      expect(loaded, hasLength(2));
      expect(
        loaded[(serverId: 'a', roomId: 'r1', threadId: 't1')],
        DateTime.utc(2026, 6, 1, 12),
      );
      expect(
        loaded[(serverId: 'b', roomId: 'r2', threadId: 't2')]!.isUtc,
        isTrue,
      );
    });

    test('preserves ids that would collide under a naive composite key',
        () async {
      final markers = {
        (serverId: 'a:b', roomId: 'r/1', threadId: 't|2'): DateTime.utc(2026),
      };
      await ThreadReadMarkerStorage.save(markers);

      final loaded = await ThreadReadMarkerStorage.load();
      expect(
        loaded[(serverId: 'a:b', roomId: 'r/1', threadId: 't|2')],
        DateTime.utc(2026),
      );
    });

    test('discards a corrupt (non-array) payload', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_read_markers': '{"not":"an array"}',
      });
      expect(await ThreadReadMarkerStorage.load(), isEmpty);
    });

    test('skips malformed rows but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_read_markers':
            '[{"s":"a","r":"r1","th":"t1","t":"2026-06-01T12:00:00Z"},'
                '{"s":"a","r":"r1"},'
                '{"s":"a","r":"r1","th":"t2","t":"not-a-date"}]',
      });
      final loaded = await ThreadReadMarkerStorage.load();
      expect(loaded, hasLength(1));
      expect(
        loaded[(serverId: 'a', roomId: 'r1', threadId: 't1')],
        DateTime.utc(2026, 6, 1, 12),
      );
    });
  });
}
