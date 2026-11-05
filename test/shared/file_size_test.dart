import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/file_size.dart';

void main() {
  group('formatFileSize', () {
    test('shows bytes below a kilobyte', () {
      expect(formatFileSize(0), '0 B');
      expect(formatFileSize(1), '1 B');
      expect(formatFileSize(1023), '1023 B');
    });

    test('counts in 1024s, one decimal under ten', () {
      expect(formatFileSize(2458), '2.4 KB');
      expect(formatFileSize(12 * 1024 + 300), '12 KB');
      expect(formatFileSize(3250585), '3.1 MB');
      expect(formatFileSize(5 * 1024 * 1024 * 1024), '5 GB');
      expect(formatFileSize(1536 * 1024 * 1024 * 1024), '1.5 TB');
    });

    test('drops a decimal of zero', () {
      expect(formatFileSize(1024), '1 KB');
      expect(formatFileSize(2048), '2 KB');
    });

    test('a value that rounds up to the next unit shows in that unit', () {
      expect(formatFileSize(1024 * 1024 - 1), '1 MB');
      expect(formatFileSize(10 * 1024 - 1), '10 KB');
    });
  });

  group('spokenFileSize', () {
    test('names the unit in words', () {
      expect(spokenFileSize(512), '512 bytes');
      expect(spokenFileSize(2458), '2.4 kilobytes');
      expect(spokenFileSize(3250585), '3.1 megabytes');
      expect(spokenFileSize(5 * 1024 * 1024 * 1024), '5 gigabytes');
      expect(spokenFileSize(1536 * 1024 * 1024 * 1024), '1.5 terabytes');
    });

    test('says one in the singular', () {
      expect(spokenFileSize(1), '1 byte');
      expect(spokenFileSize(1024), '1 kilobyte');
    });
  });
}
