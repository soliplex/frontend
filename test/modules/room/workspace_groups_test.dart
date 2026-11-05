import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/workspace_groups.dart';

WorkdirFile _file(String path, {DateTime? modifiedAt}) => WorkdirFile(
      filename: path,
      url: Uri.parse('https://example.test/$path'),
      modifiedAt: modifiedAt,
    );

List<String> _paths(List<WorkdirFile> files) =>
    [for (final f in files) f.filename];

void main() {
  group('groupByFirstFolder', () {
    test('puts root files first, then one folder per first segment', () {
      final grouped = groupByFirstFolder(descending: false, [
        _file('crm_app/README.md'),
        _file('crm_app/backend/x.py'),
        _file('notes.txt'),
        _file('reports/chart.png'),
      ]);

      expect(_paths(grouped.files), ['notes.txt']);
      expect([for (final f in grouped.folders) f.name], ['crm_app', 'reports']);
      expect(_paths(grouped.folders[0].files),
          ['crm_app/README.md', 'crm_app/backend/x.py']);
    });

    test('puts the folders that start collapsed last', () {
      final grouped = groupByFirstFolder(descending: false, [
        _file('.git/HEAD'),
        _file('__pycache__/a.pyc'),
        _file('crm_app/x.py'),
        _file('reports/a.csv'),
      ]);

      expect([for (final f in grouped.folders) f.name],
          ['crm_app', 'reports', '.git', '__pycache__']);
    });

    test('a workspace without folders has none', () {
      final grouped = groupByFirstFolder(
        [_file('a.txt'), _file('b.txt')],
        descending: false,
      );

      expect(_paths(grouped.files), ['a.txt', 'b.txt']);
      expect(grouped.folders, isEmpty);
    });

    test('orders files by name within their group, in the direction', () {
      final listing = [
        _file('src/z/a.txt'),
        _file('src/b.txt'),
        _file('b.txt'),
        _file('a.txt'),
      ];

      final up = groupByFirstFolder(listing, descending: false);
      expect(_paths(up.files), ['a.txt', 'b.txt']);
      expect(_paths(up.folders.single.files), ['src/z/a.txt', 'src/b.txt']);

      final down = groupByFirstFolder(listing, descending: true);
      expect(_paths(down.files), ['b.txt', 'a.txt']);
      expect(_paths(down.folders.single.files), ['src/b.txt', 'src/z/a.txt']);
    });

    test('orders folders by name in the direction, tooling folders last', () {
      final listing = [
        _file('__pycache__/a.pyc'),
        _file('beta/x'),
        _file('.git/HEAD'),
        _file('Alpha/x'),
      ];
      List<String> names(bool descending) => [
            for (final f
                in groupByFirstFolder(listing, descending: descending).folders)
              f.name,
          ];

      expect(names(false), ['Alpha', 'beta', '.git', '__pycache__']);
      expect(names(true), ['beta', 'Alpha', '.git', '__pycache__']);
    });

    test('puts tooling files last in their folder, in both directions', () {
      final listing = [
        _file('wt/.git'),
        _file('wt/z.txt'),
        _file('wt/sub/__pycache__/m.pyc'),
        _file('wt/a.txt'),
      ];

      final up = groupByFirstFolder(listing, descending: false);
      expect([for (final f in up.folders) f.name], ['wt']);
      expect(_paths(up.folders.single.files),
          ['wt/a.txt', 'wt/z.txt', 'wt/.git', 'wt/sub/__pycache__/m.pyc']);

      final down = groupByFirstFolder(listing, descending: true);
      expect(_paths(down.folders.single.files),
          ['wt/z.txt', 'wt/a.txt', 'wt/sub/__pycache__/m.pyc', 'wt/.git']);
    });
  });

  group('flatWorkspace', () {
    // The tooling files are the newest, so only the split keeps them last.
    final listing = [
      for (final (i, path) in [
        'a.txt',
        'b.txt',
        'src-a/main.py',
        'src-b/file',
        'src-b/another/dir/file-b',
        'src-a/under/sub/dir/.git/config',
        'src-b/__pycache__/m.pyc',
        '.git/HEAD',
      ].indexed)
        _file(path, modifiedAt: DateTime.utc(2026, 1, i + 1)),
    ];

    test('splits real files from tooling files, each by the sort', () {
      final flat = flatWorkspace(listing, FileSort.newestFirst);

      expect(_paths(flat.files), [
        'src-b/another/dir/file-b',
        'src-b/file',
        'src-a/main.py',
        'b.txt',
        'a.txt',
      ]);
      expect(_paths(flat.tooling), [
        '.git/HEAD',
        'src-b/__pycache__/m.pyc',
        'src-a/under/sub/dir/.git/config',
      ]);
    });

    test('keeps tooling files apart when the order reverses', () {
      final flat = flatWorkspace(listing, FileSort.oldestFirst);

      expect(_paths(flat.files), [
        'a.txt',
        'b.txt',
        'src-a/main.py',
        'src-b/file',
        'src-b/another/dir/file-b'
      ]);
      expect(_paths(flat.tooling), [
        'src-a/under/sub/dir/.git/config',
        'src-b/__pycache__/m.pyc',
        '.git/HEAD',
      ]);
    });
  });

  group('directoryWithin', () {
    test('drops the folder from a nested file\'s directory', () {
      expect(
        directoryWithin(_file('crm_app/backend/models/customer.py'), 'crm_app'),
        'backend/models',
      );
    });

    test('refuses a file outside the folder', () {
      // Folder `a` would otherwise read `ab/c/d.txt` as directory `/c`.
      expect(() => directoryWithin(_file('ab/c/d.txt'), 'a'),
          throwsAssertionError);
    });

    test('is null for a file directly in the folder', () {
      expect(directoryWithin(_file('crm_app/README.md'), 'crm_app'), isNull);
    });
  });

  group('startsCollapsed', () {
    test('holds for .git and __pycache__ only, matched exactly', () {
      expect(startsCollapsed('.git'), isTrue);
      expect(startsCollapsed('__pycache__'), isTrue);
      expect(startsCollapsed('.GIT'), isFalse);
      expect(startsCollapsed('git'), isFalse);
      expect(startsCollapsed('reports'), isFalse);
    });
  });

  group('isToolingPath', () {
    test('holds for a .git or __pycache__ segment at any depth', () {
      expect(isToolingPath('.git/HEAD'), isTrue);
      expect(isToolingPath('crm_app/backend/__pycache__/v.pyc'), isTrue);
    });

    test('needs a whole segment to match', () {
      expect(isToolingPath('reports/git.txt'), isFalse);
      expect(isToolingPath('__pycache__.txt'), isFalse);
      expect(isToolingPath('a.git/b.txt'), isFalse);
    });
  });
}
