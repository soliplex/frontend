import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

ThreadInfo _thread(String id) => ThreadInfo(
      id: id,
      roomId: 'room-1',
      createdAt: DateTime.utc(2026),
    );

/// Builds a page. Every bound is explicit: these tests are entirely about
/// how the bounds relate, so defaulting any of them would hide the case
/// under test.
ThreadPage _page({
  required int total,
  required int offset,
  List<ThreadInfo>? threads,
  int limit = 2,
}) =>
    ThreadPage(
      threads: threads ?? [_thread('a'), _thread('b')],
      total: total,
      limit: limit,
      offset: offset,
    );

void main() {
  group('ThreadPage', () {
    test('hasMore is true while the page does not reach the total', () {
      expect(_page(total: 3, offset: 0).hasMore, isTrue);
    });

    test('hasMore is false once the page reaches the total', () {
      // Second page of a 3-thread result: offset 2 + 1 thread == total.
      expect(
        _page(threads: [_thread('c')], total: 3, offset: 2).hasMore,
        isFalse,
      );
    });

    test('hasMore is false for an exactly-full final page', () {
      // A full page that happens to end the result must not claim more —
      // this is the case a "short page means the end" heuristic gets wrong.
      expect(_page(total: 2, offset: 0).hasMore, isFalse);
    });

    test('hasMore is false for an empty page', () {
      expect(
        _page(threads: const [], total: 0, offset: 0).hasMore,
        isFalse,
      );
    });

    test('pages with equal contents compare equal', () {
      expect(_page(total: 3, offset: 0), equals(_page(total: 3, offset: 0)));
      expect(
        _page(total: 3, offset: 0).hashCode,
        equals(_page(total: 3, offset: 0).hashCode),
      );
    });

    test('pages differing only in bounds are not equal', () {
      expect(
        _page(total: 3, offset: 0),
        isNot(equals(_page(total: 3, offset: 2))),
      );
      expect(
        _page(total: 3, offset: 0),
        isNot(equals(_page(total: 9, offset: 0))),
      );
      expect(
        _page(total: 3, offset: 0),
        isNot(equals(_page(total: 3, offset: 0, limit: 5))),
      );
    });

    test('pages differing in thread order are not equal', () {
      expect(
        _page(total: 3, offset: 0, threads: [_thread('a'), _thread('b')]),
        isNot(
          equals(
            _page(total: 3, offset: 0, threads: [_thread('b'), _thread('a')]),
          ),
        ),
      );
    });

    test('pages differing in thread count are not equal', () {
      expect(
        _page(total: 3, offset: 0, threads: [_thread('a')]),
        isNot(equals(_page(total: 3, offset: 0))),
      );
    });

    test('toString summarises the page without dumping every thread', () {
      expect(
        _page(total: 3, offset: 0).toString(),
        equals('ThreadPage(threads: 2, total: 3, limit: 2, offset: 0)'),
      );
    });
  });
}
