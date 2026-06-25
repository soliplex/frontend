// Verifies the public theming contract: tint customization must be reachable
// through the facade alone, without a direct soliplex_design dependency.
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  test('BrandTint and TintSource are exported from the facade', () {
    const theme = BrandTheme.soliplex();
    final tinted = BrandTheme(
      light: theme.light,
      dark: theme.dark,
      tint: const BrandTint(source: TintSource.primary, strength: 0.1),
    );
    expect(tinted.tint.source, TintSource.primary);
    expect(tinted.tint.strength, 0.1);
  });

  test('BrandFontRole is exported from the facade', () {
    expect(BrandFontRole.values.length, 4);
    expect(BrandFontRole.brand, isNotNull);
  });
}
