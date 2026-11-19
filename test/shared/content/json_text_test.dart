import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/content/json_text.dart';

void main() {
  group('formatJson', () {
    test('lays text out as the 2-space pretty-print does', () {
      const document = r'''
 {
  "text" : "a [b] {c}: d, \"e\"",
  "empty" : {},  "none": [ ],
  "nested": {
    "items": [1, -2.5, true, false, null, {"k": []}],
    "inner": {"x": {}}
  }
 }
''';
      expect(
        formatJson(document),
        const JsonEncoder.withIndent('  ').convert(jsonDecode(document)),
      );
    });

    test('keeps literals as written', () {
      expect(
        formatJson('[1e2,12345678901234567890,-0,1.50]'),
        '[\n  1e2,\n  12345678901234567890,\n  -0,\n  1.50\n]',
      );
    });
  });

  test('jsonNestingDepth counts brackets outside strings', () {
    const cases = {
      '1': 0,
      '[]': 1,
      '{}': 1,
      '[[1]]': 2,
      '{"a":{}}': 2,
      '["[[{"]': 1,
      r'["\"[[{"]': 1,
      '{"a":[{"b":[]}]}': 4,
    };
    for (final MapEntry(key: source, value: depth) in cases.entries) {
      expect(jsonNestingDepth(source), depth, reason: source);
    }
  });
}
