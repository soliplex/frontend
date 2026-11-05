import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

typedef _Entry = ({String path, DateTime? at, int? size});

_Entry _e(String path, {DateTime? at, int? size}) =>
    (path: path, at: at, size: size);

DateTime _t(int day) => DateTime.utc(2026, 1, day);

List<String> _sorted(List<_Entry> entries, FileSort sort) => [
      for (final e in sortFiles<_Entry>(
        entries,
        sort,
        path: (e) => e.path,
        modifiedAt: (e) => e.at,
        sizeBytes: (e) => e.size,
      ))
        e.path,
    ];

PersistedUpload _persisted(String name) => PersistedUpload(
    filename: name, url: Uri.parse('https://example.test/$name'));

void main() {
  group('FileSort.tap', () {
    test('the active key reverses; another key gives its first tap', () {
      expect(
          FileSort.foldersAToZ.tap(FileSortKey.folders), FileSort.foldersZToA);
      expect(
          FileSort.foldersAToZ.tap(FileSortKey.modified), FileSort.newestFirst);
      expect(
          FileSort.largestFirst.tap(FileSortKey.size), FileSort.smallestFirst);
      expect(FileSort.largestFirst.tap(FileSortKey.name), FileSort.nameAToZ);
    });

    test('reversed keeps the key and undoes itself', () {
      for (final s in FileSort.values) {
        expect(s.reversed.reversed, s);
        expect(s.reversed.key, s.key);
        expect(s.reversed, isNot(s));
      }
    });
  });

  group('sortFiles by name', () {
    final entries = [_e('b/zeta'), _e('a/alpha'), _e('c/alpha')];

    test('compares the file name, and the path breaks a tie', () {
      expect(
        _sorted(entries, FileSort.nameAToZ),
        ['a/alpha', 'c/alpha', 'b/zeta'],
      );
    });

    test('ignores case', () {
      expect(
        _sorted([_e('x/Zeta'), _e('y/alpha'), _e('z/Beta')], FileSort.nameAToZ),
        ['y/alpha', 'z/Beta', 'x/Zeta'],
      );
      expect(
        _sorted([_e('b/Alpha'), _e('a/alpha')], FileSort.nameAToZ),
        ['a/alpha', 'b/Alpha'],
      );
    });

    test('descending reverses the name but not the tie', () {
      expect(
        _sorted(entries, FileSort.nameZToA),
        ['b/zeta', 'a/alpha', 'c/alpha'],
      );
    });

    test('folders sort as name does', () {
      expect(
        _sorted(entries, FileSort.foldersZToA),
        ['b/zeta', 'a/alpha', 'c/alpha'],
      );
    });
  });

  group('sortFiles by modified time', () {
    final entries = [
      _e('old', at: _t(1)),
      _e('undatedB'),
      _e('new', at: _t(3)),
      _e('undatedA'),
      _e('tieB', at: _t(2)),
      _e('tieA', at: _t(2)),
    ];

    test('newest first, undated last', () {
      expect(
        _sorted(entries, FileSort.newestFirst),
        ['new', 'tieA', 'tieB', 'old', 'undatedA', 'undatedB'],
      );
    });

    test('oldest first keeps undated last and ties by path', () {
      expect(
        _sorted(entries, FileSort.oldestFirst),
        ['old', 'tieA', 'tieB', 'new', 'undatedA', 'undatedB'],
      );
    });
  });

  group('sortFiles by size', () {
    final entries = [
      _e('small', size: 1),
      _e('unsizedB'),
      _e('large', size: 3),
      _e('unsizedA'),
      _e('tieB', size: 2),
      _e('tieA', size: 2),
    ];

    test('largest first, unsized last', () {
      expect(
        _sorted(entries, FileSort.largestFirst),
        ['large', 'tieA', 'tieB', 'small', 'unsizedA', 'unsizedB'],
      );
    });

    test('smallest first keeps unsized last and ties by path', () {
      expect(
        _sorted(entries, FileSort.smallestFirst),
        ['small', 'tieA', 'tieB', 'large', 'unsizedA', 'unsizedB'],
      );
    });
  });

  group('orderUploads', () {
    const pending = PendingUpload(
      id: 'p',
      filename: 'p',
      sentBytes: 0,
      totalBytes: 1,
    );
    const failed = FailedUpload(id: 'f', filename: 'f', message: 'no');
    final uploads = <DisplayUpload>[
      _persisted('b'),
      pending,
      failed,
      _persisted('a'),
    ];

    List<String> names(List<DisplayUpload> list) =>
        [for (final u in list) u.filename];

    test('puts pending and failed rows first, then persisted by the sort', () {
      expect(names(orderUploads(uploads, FileSort.nameAToZ)), [
        'p',
        'f',
        'a',
        'b',
      ]);
    });

    test('reversing leaves pending and failed rows first', () {
      expect(names(orderUploads(uploads, FileSort.nameZToA)), [
        'p',
        'f',
        'b',
        'a',
      ]);
    });
  });

  group('effectiveSort', () {
    test('falls back to name, A to Z, for a key no entry carries', () {
      for (final s in [FileSort.newestFirst, FileSort.oldestFirst]) {
        expect(
          effectiveSort(s, hasTimes: false, hasSizes: true),
          FileSort.nameAToZ,
        );
        expect(effectiveSort(s, hasTimes: true, hasSizes: false), s);
      }
      for (final s in [FileSort.largestFirst, FileSort.smallestFirst]) {
        expect(
          effectiveSort(s, hasTimes: true, hasSizes: false),
          FileSort.nameAToZ,
        );
        expect(effectiveSort(s, hasTimes: false, hasSizes: true), s);
      }
    });

    test('keeps folders and name whatever the entries carry', () {
      for (final s in [
        FileSort.foldersAToZ,
        FileSort.foldersZToA,
        FileSort.nameAToZ,
        FileSort.nameZToA,
      ]) {
        expect(effectiveSort(s, hasTimes: false, hasSizes: false), s);
      }
    });
  });
}
