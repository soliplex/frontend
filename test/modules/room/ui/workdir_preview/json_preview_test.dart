import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/json_preview.dart';

void main() {
  group('tryPrettyPrintJson', () {
    test('reformats valid JSON with 2-space indent', () {
      const compact = '{"a":1,"b":[2,3]}';
      const expected = '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}';
      expect(tryPrettyPrintJson(compact), expected);
    });

    test('returns null when JSON is malformed', () {
      expect(tryPrettyPrintJson('{not valid json'), isNull);
    });

    test('handles top-level non-object values', () {
      expect(tryPrettyPrintJson('"hello"'), '"hello"');
      expect(tryPrettyPrintJson('42'), '42');
    });
  });

  group('JsonPreview widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('renders only the formatted block for valid JSON',
        (tester) async {
      await tester.pumpWidget(wrap(
        const JsonPreview(content: '{"a":1}'),
      ));

      expect(
        find.text("This file isn't valid JSON; showing raw contents."),
        findsNothing,
      );
    });

    testWidgets(
        'shows the malformed banner above raw contents for invalid JSON',
        (tester) async {
      await tester.pumpWidget(wrap(
        const JsonPreview(content: '{not valid json'),
      ));

      expect(
        find.text("This file isn't valid JSON; showing raw contents."),
        findsOneWidget,
      );
    });
  });
}
