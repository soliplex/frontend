import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/room/thread_anchor_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ThreadAnchorStorage', () {
    test('defaults to empty when nothing is persisted', () async {
      expect(await ThreadAnchorStorage.load(), isEmpty);
    });

    test('round-trips anchors', () async {
      final anchors = {
        (serverId: 'a', roomId: 'r1', threadId: 't1'): 'msg-1',
        (serverId: 'b', roomId: 'r2', threadId: 't2'): 'msg-2',
      };
      await ThreadAnchorStorage.save(anchors);

      final loaded = await ThreadAnchorStorage.load();
      expect(loaded, hasLength(2));
      expect(loaded[(serverId: 'a', roomId: 'r1', threadId: 't1')], 'msg-1');
      expect(loaded[(serverId: 'b', roomId: 'r2', threadId: 't2')], 'msg-2');
    });

    test('preserves ids that would collide under a naive composite key',
        () async {
      final anchors = {
        (serverId: 'a:b', roomId: 'r/1', threadId: 't|2'): 'm',
      };
      await ThreadAnchorStorage.save(anchors);

      final loaded = await ThreadAnchorStorage.load();
      expect(loaded[(serverId: 'a:b', roomId: 'r/1', threadId: 't|2')], 'm');
    });

    test('discards a corrupt (non-array) payload', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_unread_anchors': '{"not":"an array"}',
      });
      expect(await ThreadAnchorStorage.load(), isEmpty);
    });

    test('skips malformed rows but keeps valid ones', () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_unread_anchors':
            '[{"s":"a","r":"r1","th":"t1","id":"m1"},'
                '{"s":"a","r":"r1"},'
                '{"s":"a","r":"r1","th":"t2","id":123}]',
      });
      final loaded = await ThreadAnchorStorage.load();
      expect(loaded, hasLength(1));
      expect(loaded[(serverId: 'a', roomId: 'r1', threadId: 't1')], 'm1');
    });

    test('degrades to empty when every row of a non-empty payload is malformed',
        () async {
      SharedPreferences.setMockInitialValues({
        'soliplex_thread_unread_anchors':
            '[{"s":"a","r":"r1"},{"th":"t2","id":123}]',
      });
      expect(await ThreadAnchorStorage.load(), isEmpty);
    });
  });
}
