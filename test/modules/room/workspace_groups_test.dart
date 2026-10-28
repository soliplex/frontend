import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_frontend/src/modules/room/workspace_groups.dart';

WorkdirFile _file(String path) =>
    WorkdirFile(filename: path, url: Uri.parse('https://example.test/$path'));

List<String> _paths(List<WorkdirFile> files) =>
    [for (final f in files) f.filename];

void main() {
  group('groupByFirstFolder', () {
    test('puts root files first, then one folder per first segment', () {
      final grouped = groupByFirstFolder([
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
      final grouped = groupByFirstFolder([
        _file('.git/HEAD'),
        _file('__pycache__/a.pyc'),
        _file('crm_app/x.py'),
        _file('reports/a.csv'),
      ]);

      expect([for (final f in grouped.folders) f.name],
          ['crm_app', 'reports', '.git', '__pycache__']);
    });

    test('a workspace without folders has none', () {
      final grouped = groupByFirstFolder([_file('a.txt'), _file('b.txt')]);

      expect(_paths(grouped.files), ['a.txt', 'b.txt']);
      expect(grouped.folders, isEmpty);
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
      // Folder `a` would otherwise read `ab/c/d.txt` as directory `c`.
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
