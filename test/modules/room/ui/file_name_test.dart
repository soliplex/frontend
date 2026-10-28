import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';

void main() {
  group('splitExtension', () {
    test('splits a short extension off the stem', () {
      expect(splitExtension('report.dart'), ('report', '.dart'));
    });

    test('splits at the last dot only', () {
      expect(splitExtension('archive.tar.gz'), ('archive.tar', '.gz'));
    });

    test('a leading-dot name has no extension', () {
      // .bashrc has no useful stem-extension split: the extension *is* the
      // whole name.
      expect(splitExtension('.bashrc'), ('.bashrc', ''));
    });

    test('a trailing dot is no extension', () {
      expect(splitExtension('notes.'), ('notes.', ''));
    });

    test('a name without a dot has no extension', () {
      expect(splitExtension('Makefile'), ('Makefile', ''));
    });

    test('keeps an 8-char extension but not a 9-char one', () {
      // Pins the <= 8 cap precisely: a regression to < 8 or <= 9 fails one
      // of the two.
      expect(splitExtension('a.12345678'), ('a', '.12345678'));
      expect(splitExtension('a.123456789'), ('a.123456789', ''));
    });
  });

  group('FileName', () {
    test('refuses a path', () {
      // A dot in a directory segment would be taken for the extension:
      // splitExtension('v1.2/notes') is ('v1', '.2/notes').
      expect(() => FileName('v1.2/notes'), throwsAssertionError);
    });

    testWidgets('cuts an extension wider than its slot', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 20, child: FileName('a.xlsx')),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });
}
