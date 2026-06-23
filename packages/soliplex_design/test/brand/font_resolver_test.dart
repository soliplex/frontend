import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('BundledFontResolver', () {
    const resolver = BundledFontResolver();

    test('passes the family and fallback chain through to native resolution',
        () {
      final resolved = resolver.resolve('Inter', const ['Roboto', 'Arial']);
      expect(resolved.fontFamily, 'Inter');
      expect(resolved.fontFamilyFallback, const ['Roboto', 'Arial']);
    });

    test('preserves an empty fallback chain', () {
      final resolved = resolver.resolve('Fraunces', const []);
      expect(resolved.fontFamily, 'Fraunces');
      expect(resolved.fontFamilyFallback, isEmpty);
    });

    test('is a FontResolver', () {
      expect(resolver, isA<FontResolver>());
    });
  });

  group('ResolvedFont', () {
    test('equality compares the family and fallback chain by value', () {
      expect(
        const ResolvedFont(fontFamily: 'Inter', fontFamilyFallback: ['Roboto']),
        const ResolvedFont(fontFamily: 'Inter', fontFamilyFallback: ['Roboto']),
      );
      expect(
        const ResolvedFont(fontFamily: 'Inter', fontFamilyFallback: ['Roboto']),
        isNot(
          const ResolvedFont(
            fontFamily: 'Inter',
            fontFamilyFallback: ['Arial'],
          ),
        ),
      );
    });

    test('hashCode agrees with equality', () {
      expect(
        const ResolvedFont(
          fontFamily: 'Inter',
          fontFamilyFallback: ['Roboto'],
        ).hashCode,
        const ResolvedFont(
          fontFamily: 'Inter',
          fontFamilyFallback: ['Roboto'],
        ).hashCode,
      );
    });
  });
}
