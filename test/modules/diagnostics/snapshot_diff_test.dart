import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/snapshot_diff.dart';

void main() {
  group('diffSnapshots', () {
    test('null prior produces an added change per top-level key', () {
      final diff = diffSnapshots(null, {'a': 1, 'b': 2});
      expect(diff.added.map((c) => c.path).toSet(), {'/a', '/b'});
      expect(diff.removed, isEmpty);
      expect(diff.replaced, isEmpty);
    });

    test('empty prior is treated like null', () {
      final diff = diffSnapshots({}, {'a': 1});
      expect(diff.added, hasLength(1));
      expect(diff.added.single.path, '/a');
    });

    test('identical snapshots produce no changes', () {
      final diff = diffSnapshots(
        {
          'a': 1,
          'nested': {'x': true},
        },
        {
          'a': 1,
          'nested': {'x': true},
        },
      );
      expect(diff.isEmpty, isTrue);
      expect(diff.summary, 'no change');
    });

    test('detects added, removed, and replaced top-level keys', () {
      final diff = diffSnapshots(
        {'keep': 1, 'drop': 2, 'change': 'before'},
        {'keep': 1, 'change': 'after', 'add': 9},
      );
      expect(diff.added.single.path, '/add');
      expect(diff.removed.single.path, '/drop');
      expect(diff.replaced.single.path, '/change');
      expect(diff.replaced.single.before, 'before');
      expect(diff.replaced.single.after, 'after');
      expect(diff.summary, '+1 / -1 / ~1');
    });

    test('recurses into nested maps and reports leaf paths', () {
      final diff = diffSnapshots(
        {
          'ui': {
            'hud': {'mode': 'idle', 'extra': 'gone'},
          },
        },
        {
          'ui': {
            'hud': {'mode': 'active', 'new': true},
          },
        },
      );
      expect(diff.replaced.single.path, '/ui/hud/mode');
      expect(diff.added.single.path, '/ui/hud/new');
      expect(diff.removed.single.path, '/ui/hud/extra');
    });

    test('list extension is reported as added at index', () {
      final diff = diffSnapshots(
        {
          'narrations': ['a'],
        },
        {
          'narrations': ['a', 'b', 'c'],
        },
      );
      expect(
        diff.added.map((c) => c.path).toList(),
        ['/narrations/1', '/narrations/2'],
      );
    });

    test('list shrink is reported as removed at index', () {
      final diff = diffSnapshots(
        {
          'narrations': ['a', 'b', 'c'],
        },
        {
          'narrations': ['a'],
        },
      );
      expect(
        diff.removed.map((c) => c.path).toList(),
        ['/narrations/1', '/narrations/2'],
      );
    });

    test('list element replacement', () {
      final diff = diffSnapshots(
        {
          'list': [
            {'id': 1, 'name': 'old'},
          ],
        },
        {
          'list': [
            {'id': 1, 'name': 'new'},
          ],
        },
      );
      expect(diff.replaced.single.path, '/list/0/name');
      expect(diff.replaced.single.before, 'old');
      expect(diff.replaced.single.after, 'new');
    });

    test('type mismatch at a path is one replacement, no recursion', () {
      final diff = diffSnapshots(
        {
          'value': {'nested': 'map'},
        },
        {
          'value': 'now a string',
        },
      );
      expect(diff.replaced.single.path, '/value');
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });

    test('summary drops empty segments', () {
      final addedOnly = diffSnapshots({}, {'x': 1});
      expect(addedOnly.summary, '+1');

      final replacedOnly = diffSnapshots({'x': 1}, {'x': 2});
      expect(replacedOnly.summary, '~1');
    });
  });
}
