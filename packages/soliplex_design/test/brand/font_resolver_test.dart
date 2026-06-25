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
  });
}
