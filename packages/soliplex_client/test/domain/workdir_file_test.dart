import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:test/test.dart';

void main() {
  group('WorkdirFile', () {
    test('value-equality is by filename and url', () {
      final url = Uri.parse('https://example.test/output.csv');
      final otherUrl = Uri.parse('https://example.test/other.csv');
      final a = WorkdirFile(filename: 'output.csv', url: url);
      final aDup = WorkdirFile(filename: 'output.csv', url: url);
      final differentName = WorkdirFile(filename: 'other.csv', url: url);
      final differentUrl = WorkdirFile(filename: 'output.csv', url: otherUrl);
      expect(a, equals(aDup));
      expect(a.hashCode, equals(aDup.hashCode));
      expect(a, isNot(equals(differentName)));
      expect(a, isNot(equals(differentUrl)));
    });

    final url = Uri.parse('https://example.test/x');

    test('a nested file splits into its directory and basename', () {
      final file = WorkdirFile(filename: 'dir/sub/file.txt', url: url);
      expect(file.basename, 'file.txt');
      expect(file.directory, 'dir/sub');
    });

    test('a top-level file has its filename as basename and no directory', () {
      final file = WorkdirFile(filename: 'notes.txt', url: url);
      expect(file.basename, 'notes.txt');
      expect(file.directory, isNull);
    });
  });
}
