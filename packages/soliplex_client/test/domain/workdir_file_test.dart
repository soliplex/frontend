import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:test/test.dart';

void main() {
  group('WorkdirFile', () {
    test('value-equality is by filename', () {
      const a = WorkdirFile(filename: 'output.csv');
      const aDup = WorkdirFile(filename: 'output.csv');
      const b = WorkdirFile(filename: 'other.csv');
      expect(a, equals(aDup));
      expect(a.hashCode, equals(aDup.hashCode));
      expect(a, isNot(equals(b)));
    });
  });
}
