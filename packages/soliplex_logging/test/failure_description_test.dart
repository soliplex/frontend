import 'dart:convert';

import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

void main() {
  group('describeFailure', () {
    test('keeps the reason and offset of a decode failure, not the source', () {
      // The blob a truncated storage write produces: the token values sit
      // inside the window FormatException.toString() would echo.
      const blob = '{"serverUrl":"https://example.com",'
          '"tokens":{"accessToken":"eyJhbGciOiJIUzI1NiJ9.SECRET_PAYLOAD",'
          '"refreshToken":"rt_ABCDEF"} TRUNCATED';

      String described;
      try {
        jsonDecode(blob);
        fail('expected a FormatException');
      } on FormatException catch (e) {
        described = describeFailure(e);
      }

      expect(described, contains('Unexpected character'));
      expect(described, contains('offset'));
      expect(described, isNot(contains('SECRET_PAYLOAD')));
      expect(described, isNot(contains('rt_ABCDEF')));
    });

    test('omits the offset when the failure has none', () {
      String described;
      try {
        DateTime.parse('SECRET-not-a-date');
        fail('expected a FormatException');
      } on FormatException catch (e) {
        described = describeFailure(e);
      }

      expect(described, contains('Invalid date format'));
      expect(described, isNot(contains('offset')));
      expect(described, isNot(contains('SECRET')));
    });

    test('keeps a type error in full: it renders types, never values', () {
      const body = '<html>SECRET</html>';
      Object? caught;
      try {
        // The shape a non-JSON response body produces: the cast fails, and
        // the type names are what say the body arrived as a string.
        caught = (body as dynamic) as Map<String, dynamic>;
      } on Object catch (e) {
        caught = e;
      }

      expect(caught, isA<TypeError>());
      final described = describeFailure(caught);

      expect(described, contains("type 'String' is not a subtype"));
      expect(described, contains('Map<String, dynamic>'));
      expect(described, isNot(contains('SECRET')));
    });

    test('names the rejected parameter of an argument error, not its value',
        () {
      // The shape a rejected open-redirect return path produces: which field
      // was refused is the diagnosis; the value and the prose are not.
      final described = describeFailure(
        ArgumentError.value(
          'https://evil.example.com/SECRET',
          'frontendReturnTo',
          'must be an in-app path starting with "/"',
        ),
      );

      expect(described, 'ArgumentError: frontendReturnTo');
      expect(described, isNot(contains('SECRET')));
      expect(described, isNot(contains('in-app path')));
    });

    test('drops the bounds of a range error, keeping the parameter', () {
      // RangeError extends ArgumentError and embeds its value, so it must
      // route through the same arm rather than falling through.
      final described =
          describeFailure(RangeError.value(4815162342, 'pageIndex'));

      expect(described, 'RangeError: pageIndex');
      expect(described, isNot(contains('4815162342')));
    });

    test('falls back to the type when an argument error names no parameter',
        () {
      final described = describeFailure(ArgumentError('SECRET_DETAIL'));

      expect(described, 'ArgumentError');
    });

    test('reduces any other failure to its type', () {
      // The message is written by whoever threw; none of it is safe to keep.
      final described =
          describeFailure(UnsupportedError('Cannot modify SECRET_LIST'));

      expect(described, 'UnsupportedError');
      expect(described, isNot(contains('SECRET')));
    });
  });
}
