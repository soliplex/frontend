import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:test/test.dart';

void main() {
  group('WorkdirFile', () {
    test('value-equality is by filename', () {
      final a = WorkdirFile(filename: 'output.csv');
      final aDup = WorkdirFile(filename: 'output.csv');
      final b = WorkdirFile(filename: 'other.csv');
      expect(a, equals(aDup));
      expect(a.hashCode, equals(aDup.hashCode));
      expect(a, isNot(equals(b)));
    });

    group('invariants', () {
      test('asserts non-empty filename', () {
        expect(() => WorkdirFile(filename: ''), throwsA(isA<AssertionError>()));
      });

      test('asserts no path separators', () {
        expect(
          () => WorkdirFile(filename: 'sub/file.txt'),
          throwsA(isA<AssertionError>()),
        );
      });

      test('asserts no NUL bytes', () {
        expect(
          () => WorkdirFile(filename: 'a\x00b.txt'),
          throwsA(isA<AssertionError>()),
        );
      });
    });
  });
}
