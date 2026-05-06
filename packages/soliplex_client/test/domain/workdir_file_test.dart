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
  });
}
