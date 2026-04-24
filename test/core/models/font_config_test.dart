import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/models/font_config.dart';

void main() {
  group('FontConfig', () {
    test('default constructor leaves all fields null', () {
      const config = FontConfig();
      expect(config.bodyFont, isNull);
      expect(config.displayFont, isNull);
      expect(config.brandFont, isNull);
      expect(config.codeFont, isNull);
    });

    test('constructor accepts all four font roles', () {
      const config = FontConfig(
        bodyFont: 'Inter',
        displayFont: 'Oswald',
        brandFont: 'SquadaOne',
        codeFont: 'JetBrains Mono',
      );
      expect(config.bodyFont, 'Inter');
      expect(config.displayFont, 'Oswald');
      expect(config.brandFont, 'SquadaOne');
      expect(config.codeFont, 'JetBrains Mono');
    });

    group('copyWith', () {
      const original = FontConfig(
        bodyFont: 'Inter',
        displayFont: 'Oswald',
        brandFont: 'SquadaOne',
        codeFont: 'JetBrains Mono',
      );

      test('returns identical config when no args provided', () {
        final copy = original.copyWith();
        expect(copy, original);
      });

      test('updates bodyFont only', () {
        final copy = original.copyWith(bodyFont: 'Roboto');
        expect(copy.bodyFont, 'Roboto');
        expect(copy.displayFont, 'Oswald');
        expect(copy.brandFont, 'SquadaOne');
        expect(copy.codeFont, 'JetBrains Mono');
      });

      test('updates displayFont only', () {
        final copy = original.copyWith(displayFont: 'Lato');
        expect(copy.displayFont, 'Lato');
        expect(copy.bodyFont, 'Inter');
      });

      test('updates brandFont only', () {
        final copy = original.copyWith(brandFont: 'Bebas Neue');
        expect(copy.brandFont, 'Bebas Neue');
      });

      test('updates codeFont only', () {
        final copy = original.copyWith(codeFont: 'Fira Code');
        expect(copy.codeFont, 'Fira Code');
      });

      test('clearBodyFont resets bodyFont to null', () {
        final copy = original.copyWith(clearBodyFont: true);
        expect(copy.bodyFont, isNull);
        expect(copy.displayFont, 'Oswald');
      });

      test('clearDisplayFont resets displayFont to null', () {
        final copy = original.copyWith(clearDisplayFont: true);
        expect(copy.displayFont, isNull);
      });

      test('clearBrandFont resets brandFont to null', () {
        final copy = original.copyWith(clearBrandFont: true);
        expect(copy.brandFont, isNull);
      });

      test('clearCodeFont resets codeFont to null', () {
        final copy = original.copyWith(clearCodeFont: true);
        expect(copy.codeFont, isNull);
      });

      test('clear flags take precedence over new values', () {
        final copy = original.copyWith(
          bodyFont: 'Roboto',
          clearBodyFont: true,
        );
        expect(copy.bodyFont, isNull);
      });
    });

    group('equality', () {
      test('two configs with same values are equal', () {
        const a = FontConfig(bodyFont: 'Inter', codeFont: 'Fira Code');
        const b = FontConfig(bodyFont: 'Inter', codeFont: 'Fira Code');
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('configs with different bodyFont are not equal', () {
        const a = FontConfig(bodyFont: 'Inter');
        const b = FontConfig(bodyFont: 'Roboto');
        expect(a, isNot(b));
      });

      test('configs with different codeFont are not equal', () {
        const a = FontConfig(codeFont: 'Fira Code');
        const b = FontConfig(codeFont: 'JetBrains Mono');
        expect(a, isNot(b));
      });

      test('default config equals another default config', () {
        expect(const FontConfig(), const FontConfig());
      });
    });

    test('toString includes all four roles', () {
      const config = FontConfig(
        bodyFont: 'Inter',
        displayFont: 'Oswald',
        brandFont: 'SquadaOne',
        codeFont: 'JetBrains Mono',
      );
      final str = config.toString();
      expect(str, contains('bodyFont: Inter'));
      expect(str, contains('displayFont: Oswald'));
      expect(str, contains('brandFont: SquadaOne'));
      expect(str, contains('codeFont: JetBrains Mono'));
    });
  });
}
