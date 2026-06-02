import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('DatasetMarking', () {
    test('labels use the exact authoritative text', () {
      expect(DatasetMarking.unclassified.label, 'UNCLASSIFIED');
      expect(DatasetMarking.cui.label, 'CUI');
      expect(DatasetMarking.confidential.label, 'CONFIDENTIAL');
      expect(DatasetMarking.secret.label, 'SECRET');
      expect(DatasetMarking.topSecret.label, 'TOP SECRET');
      expect(DatasetMarking.topSecretSci.label, 'TOP SECRET//SCI');
    });

    test('portion labels are parenthesised', () {
      expect(DatasetMarking.unclassified.portionLabel, '(U)');
      expect(DatasetMarking.cui.portionLabel, '(CUI)');
      expect(DatasetMarking.secret.portionLabel, '(S)');
      expect(DatasetMarking.topSecretSci.portionLabel, '(TS//SCI)');
    });

    test('severity increases with restrictiveness', () {
      expect(
        DatasetMarking.unclassified.severity < DatasetMarking.cui.severity,
        isTrue,
      );
      expect(
        DatasetMarking.secret.severity < DatasetMarking.topSecretSci.severity,
        isTrue,
      );
    });

    group('highestOf', () {
      test('returns the most restrictive marking', () {
        expect(
          DatasetMarking.highestOf([
            DatasetMarking.unclassified,
            DatasetMarking.secret,
            DatasetMarking.cui,
          ]),
          DatasetMarking.secret,
        );
      });

      test('defaults to unclassified when empty', () {
        expect(DatasetMarking.highestOf([]), DatasetMarking.unclassified);
      });
    });

    group('isMixed', () {
      test('false for a uniform set', () {
        expect(
          DatasetMarking.isMixed([DatasetMarking.cui, DatasetMarking.cui]),
          isFalse,
        );
      });

      test('true when markings differ', () {
        expect(
          DatasetMarking.isMixed(
            [DatasetMarking.cui, DatasetMarking.secret],
          ),
          isTrue,
        );
      });
    });

    test('the default palette resolves a pair for every marking', () {
      for (final marking in DatasetMarking.values) {
        expect(SoliplexMarkingColors.dod.resolve(marking), isNotNull);
      }
    });

    test('default color values match the DoD palette', () {
      const dod = SoliplexMarkingColors.dod;
      expect(
        dod.resolve(DatasetMarking.unclassified).background,
        const Color(0xFF007A33),
      );
      expect(
        dod.resolve(DatasetMarking.cui).background,
        const Color(0xFF502B85),
      );
      expect(
        dod.resolve(DatasetMarking.topSecret).foreground,
        const Color(0xFF000000),
      );
    });

    test('copyWith overrides only the given markings (white-label path)', () {
      final custom = SoliplexMarkingColors.dod.copyWith(
        cui: const SoliplexMarkingColor(
          background: Color(0xFF112233),
          foreground: Color(0xFFFFFFFF),
        ),
      );
      // Overridden marking changes...
      expect(
        custom.resolve(DatasetMarking.cui).background,
        const Color(0xFF112233),
      );
      // ...others keep the DoD default.
      expect(
        custom.resolve(DatasetMarking.secret).background,
        SoliplexMarkingColors.dod.resolve(DatasetMarking.secret).background,
      );
    });
  });
}
