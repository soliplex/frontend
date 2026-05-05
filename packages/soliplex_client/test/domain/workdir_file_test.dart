import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:test/test.dart';

void main() {
  group('WorkdirFile', () {
    group('equality', () {
      test('equals by filename and url', () {
        final a = WorkdirFile(
          filename: 'output.csv',
          url: Uri.parse(
            'https://example.com/workdirs/room/thread/run/output.csv',
          ),
        );
        final b = WorkdirFile(
          filename: 'output.csv',
          url: Uri.parse(
            'https://example.com/workdirs/room/thread/run/output.csv',
          ),
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('not equals with different filename', () {
        final a = WorkdirFile(
          filename: 'a.csv',
          url: Uri.parse('https://example.com/a'),
        );
        final b = WorkdirFile(
          filename: 'b.csv',
          url: Uri.parse('https://example.com/a'),
        );

        expect(a, isNot(equals(b)));
      });

      test('not equals with different url', () {
        final a = WorkdirFile(
          filename: 'a.csv',
          url: Uri.parse('https://example.com/a'),
        );
        final b = WorkdirFile(
          filename: 'a.csv',
          url: Uri.parse('https://example.com/b'),
        );

        expect(a, isNot(equals(b)));
      });
    });
  });
}
