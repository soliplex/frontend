import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/bus_filter.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/bus_inspector.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/snapshot_diff.dart';

BusEvent _event({
  String server = 'srv',
  String room = 'weather',
  String thread = 'thread-abc123',
  String? tag = 'agui.snapshot',
  Map<String, dynamic> snapshot = const {},
}) =>
    BusEvent(
      timestamp: DateTime.utc(2026, 5, 1),
      threadKey: (serverId: server, roomId: room, threadId: thread),
      tag: tag,
      snapshot: snapshot,
    );

void main() {
  group('parseBusFilter', () {
    test('empty input yields empty filter', () {
      expect(parseBusFilter('').isEmpty, isTrue);
      expect(parseBusFilter('   ').isEmpty, isTrue);
    });

    test('parses each known key prefix', () {
      final f = parseBusFilter(
          'thread:abc room:weather server:srv tag:agui.snapshot path:/ui');
      expect(f.threadSubstr, 'abc');
      expect(f.roomSubstr, 'weather');
      expect(f.serverSubstr, 'srv');
      expect(f.tagPattern!.value, 'agui.snapshot');
      expect(f.tagPattern!.isPrefix, isFalse);
      expect(f.pathSubstr, '/ui');
      expect(f.bareTerms, isEmpty);
    });

    test('tag glob with trailing * is a prefix pattern', () {
      final f = parseBusFilter('tag:agui.*');
      expect(f.tagPattern!.value, 'agui.');
      expect(f.tagPattern!.isPrefix, isTrue);
    });

    test('unknown prefixes fall through to bareTerms', () {
      final f = parseBusFilter('foo:bar plain');
      expect(f.bareTerms, ['foo:bar', 'plain']);
    });

    test('later occurrence of same key overrides earlier', () {
      final f = parseBusFilter('thread:aaa thread:bbb');
      expect(f.threadSubstr, 'bbb');
    });

    test('empty value (key:) is treated as bare token', () {
      final f = parseBusFilter('thread:');
      // colon is at position len-1 → not a recognised k:v pair.
      expect(f.bareTerms, ['thread:']);
      expect(f.threadSubstr, isNull);
    });
  });

  group('BusFilter.matches', () {
    test('empty filter matches everything', () {
      expect(
        BusFilter.empty
            .matches(_event(), const SnapshotDiff.empty()),
        isTrue,
      );
    });

    test('thread substring is case-insensitive', () {
      final f = parseBusFilter('thread:ABC');
      expect(f.matches(_event(), const SnapshotDiff.empty()), isTrue);
      expect(
        f.matches(_event(thread: 'thread-xyz'), const SnapshotDiff.empty()),
        isFalse,
      );
    });

    test('room and server substrings filter independently', () {
      final f = parseBusFilter('room:weather server:srv');
      expect(f.matches(_event(), const SnapshotDiff.empty()), isTrue);
      expect(
        f.matches(_event(room: 'maps'), const SnapshotDiff.empty()),
        isFalse,
      );
      expect(
        f.matches(_event(server: 'other'), const SnapshotDiff.empty()),
        isFalse,
      );
    });

    test('tag exact match', () {
      final f = parseBusFilter('tag:agui.snapshot');
      expect(f.matches(_event(), const SnapshotDiff.empty()), isTrue);
      expect(
        f.matches(_event(tag: 'seed.initial'), const SnapshotDiff.empty()),
        isFalse,
      );
    });

    test('tag prefix glob', () {
      final f = parseBusFilter('tag:seed.*');
      expect(
        f.matches(_event(tag: 'seed.initial'), const SnapshotDiff.empty()),
        isTrue,
      );
      expect(
        f.matches(_event(tag: 'seed.history'), const SnapshotDiff.empty()),
        isTrue,
      );
      expect(
        f.matches(_event(tag: 'agui.snapshot'), const SnapshotDiff.empty()),
        isFalse,
      );
    });

    test('null tag never matches a tag pattern', () {
      final f = parseBusFilter('tag:agui.*');
      expect(
        f.matches(_event(tag: null), const SnapshotDiff.empty()),
        isFalse,
      );
    });

    test('path filter scans all change kinds', () {
      final diff = diffSnapshots(
        {'a': 1},
        {
          'a': 2, // replaced /a
          'ui': {'narrations': true}, // added /ui, /ui/narrations
        },
      );
      final f = parseBusFilter('path:narrations');
      expect(f.matches(_event(), diff), isTrue);
      final g = parseBusFilter('path:nope');
      expect(g.matches(_event(), diff), isFalse);
    });

    test('bare term must match at least one field', () {
      final diff = diffSnapshots({}, {
        'rag': {'q': 'temperature'},
      });
      final f = parseBusFilter('weather');
      expect(f.matches(_event(), diff), isTrue); // matches roomId

      final g = parseBusFilter('rag');
      expect(g.matches(_event(), diff), isTrue); // matches a path

      final h = parseBusFilter('zzz');
      expect(h.matches(_event(), diff), isFalse);
    });

    test('multiple bare terms must each match somewhere', () {
      final f = parseBusFilter('weather agui');
      expect(
        f.matches(_event(), const SnapshotDiff.empty()),
        isTrue, // 'weather' in roomId, 'agui' in tag
      );
      final g = parseBusFilter('weather missing');
      expect(g.matches(_event(), const SnapshotDiff.empty()), isFalse);
    });
  });

  group('suggestionsFor', () {
    final events = [
      _event(thread: 'thread-aaaa11', room: 'weather', tag: 'agui.snapshot'),
      _event(thread: 'thread-bbbb22', room: 'maps', tag: 'seed.initial'),
      _event(thread: 'thread-cccc33', room: 'maps', tag: null),
    ];

    test('empty input lists all key prefixes', () {
      final s = suggestionsFor(text: '', cursor: 0, events: events);
      expect(s, equals(kFilterKeys.map((k) => '$k:').toList()));
    });

    test('partial bare token suggests matching keys', () {
      final s = suggestionsFor(text: 'thr', cursor: 3, events: events);
      expect(s, ['thread:']);
    });

    test('"key:" with empty value lists known values', () {
      final s = suggestionsFor(text: 'tag:', cursor: 4, events: events);
      expect(s.toSet(), {'tag:agui.snapshot', 'tag:seed.initial'});
    });

    test('"key:partial" filters by substring', () {
      final s =
          suggestionsFor(text: 'thread:bb', cursor: 9, events: events);
      // last 6 chars of thread-bbbb22 -> 'bbbb22'
      expect(s, ['thread:bbbb22']);
    });

    test('null tags are not suggested for tag:', () {
      final s = suggestionsFor(text: 'tag:', cursor: 4, events: events);
      expect(s.where((v) => v.contains('null')), isEmpty);
    });

    test('cursor in whitespace returns key list', () {
      final s = suggestionsFor(
        text: 'thread:abc ',
        cursor: 11,
        events: events,
      );
      expect(s, equals(kFilterKeys.map((k) => '$k:').toList()));
    });
  });
}
