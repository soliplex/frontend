import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_design/src/brand/brand_lowering.dart';

Future<SoliplexRadii> _radiiUnder(WidgetTester tester, ThemeData? theme) async {
  late SoliplexRadii radii;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          radii = context.radii;
          return const SizedBox();
        },
      ),
    ),
  );
  return radii;
}

void main() {
  group('context.radii', () {
    testWidgets('reads the active theme radii', (tester) async {
      final theme = lower(
        const BrandTheme(
          light: BrandColorScheme(
            primary: Color(0xFF030213),
            secondary: Color(0xFFF3F3FA),
            background: Color(0xFFFFFFFF),
            foreground: Color(0xFF0A0A0A),
            muted: Color(0xFFECECF0),
            mutedForeground: Color(0xFF595968),
            border: Color(0x1A000000),
            onPrimary: Color(0xFFFFFFFF),
            onSecondary: Color(0xFF030213),
          ),
          dark: BrandColorScheme(
            primary: Color(0xFFFAFAFA),
            secondary: Color(0xFF2A2A2A),
            background: Color(0xFF111111),
            foreground: Color(0xFFFAFAFA),
            muted: Color(0xFF444444),
            mutedForeground: Color(0xFFAAAAAA),
            border: Color(0xFF2A2A2A),
            onPrimary: Color(0xFF222222),
            onSecondary: Color(0xFFFFFFFF),
          ),
          shape: BrandShape.square(),
        ),
        Brightness.light,
      );

      final radii = await _radiiUnder(tester, theme);
      expect(radii.md, 0);
    });

    testWidgets('falls back to the default scale when unthemed',
        (tester) async {
      final radii = await _radiiUnder(tester, null);
      expect(radii.md, soliplexRadii.md);
    });
  });
}
