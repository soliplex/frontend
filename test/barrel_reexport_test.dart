import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

/// Pins the public export contract at compile time: if the barrel stops
/// exporting one of these symbols, this file stops compiling. The runtime
/// expectations are incidental.
void main() {
  test('the flavor-authoring surface is reachable via the main barrel', () {
    final colors =
        lightSoliplexColors.copyWith(primary: const Color(0xFF0A7AFF));
    // Each reference is the pin — a dropped export fails to compile here. The
    // full-control theme surface a fork needs, and the flavor catalog it builds
    // on, both resolve through the single `soliplex_frontend` barrel.
    expect(buildSoliplexThemeData(colors: colors, brightness: Brightness.light),
        isA<ThemeData>());
    expect(darkSoliplexColors, isA<SoliplexColors>());
    expect(const SoliplexRadii(sm: 6, md: 12, lg: 16, xl: 24), isNotNull);
    expect(soliplexTextTheme(colors), isA<TextTheme>());
    expect(standard, isA<Function>());
    expect(standardFlavor, isA<Function>());
    expect(buildStandardKit, isA<Function>());
  });
}
