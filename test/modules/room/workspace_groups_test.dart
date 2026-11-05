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

List<String> _names(List<WorkspaceFolder> folders) =>
    [for (final f in folders) f.name];

void main() {
  group('workspaceTree', () {
    test('puts root files in the root, then one folder per first segment', () {
      final root = workspaceTree(descending: false, [
        _file('crm_app/README.md'),
        _file('crm_app/backend/x.py'),
        _file('notes.txt'),
        _file('reports/chart.png'),
      ]);

      expect(root.path, '');
      expect(_paths(root.files), ['notes.txt']);
      expect(_names(root.folders), ['crm_app', 'reports']);
      expect(_paths(root.folders[0].files), ['crm_app/README.md']);
      expect(_names(root.folders[0].folders), ['backend']);
      expect(root.folders[0].folders.single.path, 'crm_app/backend');
    });

    test('a workspace without folders has none', () {
      final root =
          workspaceTree([_file('a.txt'), _file('b.txt')], descending: false);

      expect(_paths(root.files), ['a.txt', 'b.txt']);
      expect(root.folders, isEmpty);
    });

    test('orders files by name within their folder, in the direction', () {
      final listing = [
        _file('src/z/a.txt'),
        _file('src/z/b.txt'),
        _file('src/c.txt'),
        _file('src/d.txt'),
        _file('b.txt'),
        _file('a.txt'),
      ];

      final up = workspaceTree(listing, descending: false);
      expect(_paths(up.files), ['a.txt', 'b.txt']);
      expect(_paths(up.folders.single.files), ['src/c.txt', 'src/d.txt']);
      expect(_paths(up.folders.single.folders.single.files),
          ['src/z/a.txt', 'src/z/b.txt']);

      final down = workspaceTree(listing, descending: true);
      expect(_paths(down.files), ['b.txt', 'a.txt']);
      expect(_paths(down.folders.single.files), ['src/d.txt', 'src/c.txt']);
      expect(_paths(down.folders.single.folders.single.files),
          ['src/z/b.txt', 'src/z/a.txt']);
    });

    test('orders folders by name in the direction, tooling folders last', () {
      final listing = [
        _file('__pycache__/a.pyc'),
        _file('beta/x'),
        _file('.git/HEAD'),
        _file('Alpha/x'),
        _file('Alpha/__pycache__/y.pyc'),
        _file('Alpha/sub-b/z'),
        _file('Alpha/.git/HEAD'),
        _file('Alpha/sub-a/z'),
      ];

      final up = workspaceTree(listing, descending: false);
      expect(_names(up.folders), ['Alpha', 'beta', '.git', '__pycache__']);
      expect(_names(up.folders[0].folders),
          ['sub-a', 'sub-b', '.git', '__pycache__']);

      final down = workspaceTree(listing, descending: true);
      expect(_names(down.folders), ['beta', 'Alpha', '.git', '__pycache__']);
      expect(_names(down.folders[1].folders),
          ['sub-b', 'sub-a', '.git', '__pycache__']);
    });

    test('puts files named for tooling last in their folder', () {
      final listing = [_file('wt/.git'), _file('wt/z.txt'), _file('wt/a.txt')];

      expect(
          _paths(
              workspaceTree(listing, descending: false).folders.single.files),
          ['wt/a.txt', 'wt/z.txt', 'wt/.git']);
      expect(
          _paths(workspaceTree(listing, descending: true).folders.single.files),
          ['wt/z.txt', 'wt/a.txt', 'wt/.git']);
    });

    test('a file named .git makes no folder', () {
      final root = workspaceTree(descending: false, [_file('.git')]);

      expect(_paths(root.files), ['.git']);
      expect(root.folders, isEmpty);
    });

    test('merges a chain of folders that each hold only one folder', () {
      final root = workspaceTree(descending: false, [
        _file('raw/archive/2023/a.csv'),
        _file('raw/archive/2023/b.csv'),
      ]);

      final chain = root.folders.single;
      expect(chain.name, 'raw/archive/2023');
      expect(chain.path, 'raw/archive/2023');
      expect(_paths(chain.files),
          ['raw/archive/2023/a.csv', 'raw/archive/2023/b.csv']);
      expect(chain.folders, isEmpty);
    });

    test('a nested chain is named from its parent and keyed by its full path',
        () {
      final root = workspaceTree(descending: false, [
        _file('src/main.py'),
        _file('src/pkg/core/models/user.py'),
      ]);

      final chain = root.folders.single.folders.single;
      expect(chain.name, 'pkg/core/models');
      expect(chain.path, 'src/pkg/core/models');
    });

    test('a chain stops at a folder that holds files of its own', () {
      final root = workspaceTree(descending: false, [
        _file('raw/notes.txt'),
        _file('raw/archive/2023/a.csv'),
      ]);

      expect(_names(root.folders), ['raw']);
      expect(_names(root.folders.single.folders), ['archive/2023']);
    });

    test('a chain stops at a folder that holds two folders', () {
      final root = workspaceTree(descending: false, [
        _file('raw/a/x.csv'),
        _file('raw/b/y.csv'),
      ]);

      expect(_names(root.folders), ['raw']);
      expect(_names(root.folders.single.folders), ['a', 'b']);
    });

    test('a chain stops before a tooling folder', () {
      final root =
          workspaceTree(descending: false, [_file('pkg/__pycache__/m.pyc')]);

      expect(_names(root.folders), ['pkg']);
      expect(root.folders.single.folders.single.path, 'pkg/__pycache__');
    });

    test('a chain that starts at a tooling folder merges', () {
      final root =
          workspaceTree(descending: false, [_file('.git/refs/heads/main')]);

      expect(_names(root.folders), ['.git/refs/heads']);
    });

    test('a merged chain sorts by its first folder', () {
      final listing = [
        _file('b/z/x.csv'),
        _file('c/y.csv'),
        _file('a/y.csv'),
      ];

      expect(_names(workspaceTree(listing, descending: false).folders),
          ['a', 'b/z', 'c']);
      expect(_names(workspaceTree(listing, descending: true).folders),
          ['c', 'b/z', 'a']);
    });

    test('a folder counts every file below it, and its own', () {
      final root = workspaceTree(descending: false, [
        _file('notes.txt'),
        _file('reports/a.csv'),
        _file('reports/q1/b.csv'),
        _file('reports/q1/deep/c.csv'),
      ]);

      expect(root.folders.single.fileCount, 3);
      expect(root.fileCount, 4);
    });

    test('a folder\'s latest change is its newest file at any depth', () {
      final newest = DateTime.utc(2026, 3);
      final root = workspaceTree(descending: false, [
        _file('reports/a.csv', modifiedAt: DateTime.utc(2026, 2)),
        _file('reports/q1/b.csv'),
        _file('reports/q1/deep/c.csv', modifiedAt: newest),
        _file('reports/q1/deep/d.csv', modifiedAt: DateTime.utc(2026)),
      ]);

      expect(root.folders.single.latestChange, newest);
    });

    test('a folder whose files have no time has no latest change', () {
      final root =
          workspaceTree(descending: false, [_file('reports/q1/b.csv')]);

      expect(root.folders.single.latestChange, isNull);
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

  group('isFolderExpanded', () {
    test('a top-level folder starts open', () {
      expect(isFolderExpanded({}, 'reports', topLevel: true), isTrue);
      expect(isFolderExpanded({}, 'raw/archive', topLevel: true), isTrue);
    });

    test('a nested folder starts closed', () {
      expect(isFolderExpanded({}, 'reports/q1', topLevel: false), isFalse);
    });

    test('a top-level tooling folder starts closed', () {
      expect(isFolderExpanded({}, '.git', topLevel: true), isFalse);
      expect(isFolderExpanded({}, '__pycache__', topLevel: true), isFalse);
      expect(isFolderExpanded({}, '.git/refs', topLevel: true), isFalse);
    });

    test('a toggle wins over where the folder starts', () {
      expect(isFolderExpanded({'reports': false}, 'reports', topLevel: true),
          isFalse);
      expect(isFolderExpanded({'a/b': true}, 'a/b', topLevel: false), isTrue);
      expect(isFolderExpanded({'.git': true}, '.git', topLevel: true), isTrue);
    });
  });

  group('ancestorsOf', () {
    test('lists every folder above a file, outermost first', () {
      expect(ancestorsOf(_file('a/b/c/d.txt')), ['a', 'a/b', 'a/b/c']);
    });

    test('is empty for a root file', () {
      expect(ancestorsOf(_file('d.txt')), isEmpty);
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
