import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/flavors.dart';

void main() {
  test('flavor-authoring surface is reachable via the barrel', () {
    final colors =
        lightSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF));
    final theme =
        buildSoliplexThemeData(colors: colors, brightness: Brightness.light);
    // Extension attachment is covered by shell_config_test; here we only
    // verify the flavor-authoring symbols resolve via the barrel.
    expect(theme, isA<ThemeData>());
    expect(darkSoliplexColors, isA<SoliplexColors>());
    expect(const SoliplexRadii(sm: 6, md: 12, lg: 16, xl: 24), isNotNull);
    expect(soliplexTextTheme(colors), isA<TextTheme>());
    // Kit symbol is a reachable type reference:
    expect(buildStandardModules, isA<Function>());
  });
}
