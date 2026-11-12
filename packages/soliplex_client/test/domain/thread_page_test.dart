import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

ThreadInfo _thread(String id) => ThreadInfo(
      id: id,
      roomId: 'room-1',
      createdAt: DateTime.utc(2026),
    );

ThreadPage _page({List<ThreadInfo>? threads, String? nextCursor}) => ThreadPage(
      threads: threads ?? [_thread('a'), _thread('b')],
      nextCursor: nextCursor,
    );

void main() {
  group('ThreadPage', () {
    test("can't be changed through its own list or the caller's", () {
      final threads = [_thread('a')];
      final page = ThreadPage(threads: threads);

      threads.add(_thread('b'));

      expect(page.threads.map((t) => t.id), equals(['a']));
      expect(() => page.threads[0] = _thread('x'), throwsUnsupportedError);
    });

    test('hasMore follows the cursor', () {
      expect(_page(nextCursor: 'c1').hasMore, isTrue);
      expect(_page().hasMore, isFalse);
    });

    test('pages with equal contents compare equal', () {
      expect(_page(nextCursor: 'c1'), equals(_page(nextCursor: 'c1')));
      expect(
        _page(nextCursor: 'c1').hashCode,
        equals(_page(nextCursor: 'c1').hashCode),
      );
    });

    test('pages differing only in cursor are not equal', () {
      expect(_page(nextCursor: 'c1'), isNot(equals(_page(nextCursor: 'c2'))));
      expect(_page(nextCursor: 'c1'), isNot(equals(_page())));
    });

    test('pages differing in thread order are not equal', () {
      expect(
        _page(threads: [_thread('a'), _thread('b')]),
        isNot(equals(_page(threads: [_thread('b'), _thread('a')]))),
      );
    });

    test('pages differing in thread count are not equal', () {
      expect(_page(threads: [_thread('a')]), isNot(equals(_page())));
    });

    test('toString summarises the page without dumping every thread', () {
      expect(
        _page(nextCursor: 'c1').toString(),
        equals('ThreadPage(threads: 2, hasMore: true)'),
      );
    });
  });
}
