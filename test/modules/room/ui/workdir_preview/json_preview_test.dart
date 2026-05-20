import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/json_preview.dart';

void main() {
  group('prettyPrintJsonOrRaw', () {
    test('reformats valid JSON with 2-space indent', () {
      const compact = '{"a":1,"b":[2,3]}';
      const expected = '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}';
      expect(prettyPrintJsonOrRaw(compact), expected);
    });

    test('returns the raw string when JSON is malformed', () {
      const broken = '{not valid json';
      expect(prettyPrintJsonOrRaw(broken), broken);
    });

    test('handles top-level non-object values', () {
      expect(prettyPrintJsonOrRaw('"hello"'), '"hello"');
      expect(prettyPrintJsonOrRaw('42'), '42');
    });
  });
}
