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

  group('splitForCut', () {
    test('keeps the end of the stem with the extension', () {
      // Names an agent writes often differ only there.
      expect(
        splitForCut('output_20261105_1432.csv'),
        ('output_2026110', '5_1432.csv'),
      );
    });

    test('keeps the whole of a short name', () {
      expect(splitForCut('a.md'), ('', 'a.md'));
    });

    test('keeps the end of a name without an extension', () {
      expect(splitForCut('Makefile_backup'), ('Makefile_', 'backup'));
    });

    test('counts what a reader sees as one character', () {
      // Each thumb with its skin tone is four UTF-16 code units: counting
      // those would split one.
      expect(
        splitForCut('notes_\u{1F44D}\u{1F3FD}\u{1F44D}\u{1F3FD}.md'),
        ('no', 'tes_\u{1F44D}\u{1F3FD}\u{1F44D}\u{1F3FD}.md'),
      );
    });
  });

  group('FileName', () {
    test('refuses a path', () {
      // A row shows a file's directory apart from its name, so FileName
      // takes the name alone.
      expect(() => FileName('v1.2/notes'), throwsAssertionError);
    });

    testWidgets('a screen reader hears the whole name, not its two parts',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 120,
                child: FileName('quarterly_report_final.xlsx'),
              ),
            ),
          ),
        ));

        expect(
          find.bySemanticsLabel('quarterly_report_final.xlsx'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('_final.xlsx'), findsNothing);
      } finally {
        semantics.dispose();
      }
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
