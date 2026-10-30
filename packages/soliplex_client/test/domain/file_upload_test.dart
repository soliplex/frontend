import 'package:soliplex_client/src/domain/file_upload.dart';
import 'package:test/test.dart';

void main() {
  group('FileUpload', () {
    group('equality', () {
      test('equals by filename and url', () {
        final a = FileUpload(
          filename: 'report.pdf',
          url: Uri.parse('https://example.com/rooms/r/uploads/report.pdf'),
        );
        final b = FileUpload(
          filename: 'report.pdf',
          url: Uri.parse('https://example.com/rooms/r/uploads/report.pdf'),
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('not equals with different filename', () {
        final a = FileUpload(
          filename: 'a.pdf',
          url: Uri.parse('https://example.com/a'),
        );
        final b = FileUpload(
          filename: 'b.pdf',
          url: Uri.parse('https://example.com/a'),
        );

        expect(a, isNot(equals(b)));
      });

      test('not equals with different url', () {
        final a = FileUpload(
          filename: 'a.pdf',
          url: Uri.parse('https://example.com/a'),
        );
        final b = FileUpload(
          filename: 'a.pdf',
          url: Uri.parse('https://example.com/b'),
        );

        expect(a, isNot(equals(b)));
      });

      test('equal instances with modifiedAt and sizeBytes share a hashCode',
          () {
        final url = Uri.parse('https://example.com/a');
        final a = FileUpload(
          filename: 'a.pdf',
          url: url,
          modifiedAt: DateTime.utc(2026, 10, 29),
          sizeBytes: 1,
        );
        final b = FileUpload(
          filename: 'a.pdf',
          url: url,
          modifiedAt: DateTime.utc(2026, 10, 29),
          sizeBytes: 1,
        );

        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('not equals with different modifiedAt', () {
        final url = Uri.parse('https://example.com/a');
        final a = FileUpload(
          filename: 'a.pdf',
          url: url,
          modifiedAt: DateTime.utc(2026, 10, 29),
        );
        final b = FileUpload(
          filename: 'a.pdf',
          url: url,
          modifiedAt: DateTime.utc(2026, 10, 30),
        );

        expect(a, isNot(equals(b)));
      });

      test('not equals with different sizeBytes', () {
        final url = Uri.parse('https://example.com/a');
        final a = FileUpload(filename: 'a.pdf', url: url, sizeBytes: 1);
        final b = FileUpload(filename: 'a.pdf', url: url, sizeBytes: 2);

        expect(a, isNot(equals(b)));
      });
    });
  });
}
