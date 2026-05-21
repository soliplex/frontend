import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/branding.dart';
import 'package:soliplex_frontend/src/design/effects/glow.dart';
import 'package:soliplex_frontend/src/design/tokens/colors.dart';

void main() {
  group('BrandLogo', () {
    const lightLogo = Text('LIGHT');
    const darkLogo = Text('DARK');

    Widget wrap(Widget child, {required Brightness brightness}) {
      return MaterialApp(
        theme: brightness == Brightness.light
            ? ThemeData.light()
            : ThemeData.dark(),
        home: Scaffold(body: child),
      );
    }

    testWidgets('light mode renders logoLight bare', (tester) async {
      const branding = SoliplexBranding(
        accentLight: Colors.blue,
        accentDark: Colors.indigo,
        appName: 'X',
        logoLight: lightLogo,
        logoDark: darkLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(branding: branding), brightness: Brightness.light),
      );
      expect(find.text('LIGHT'), findsOneWidget);
      expect(find.text('DARK'), findsNothing);
      expect(find.byType(SoliplexGlow), findsNothing);
    });

    testWidgets('dark mode prefers logoDark when provided', (tester) async {
      const branding = SoliplexBranding(
        accentLight: Colors.blue,
        accentDark: Colors.indigo,
        appName: 'X',
        logoLight: lightLogo,
        logoDark: darkLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(branding: branding), brightness: Brightness.dark),
      );
      expect(find.text('DARK'), findsOneWidget);
      expect(find.byType(SoliplexGlow), findsNothing);
    });

    testWidgets('dark mode wraps logoLight in SoliplexGlow when no logoDark',
        (tester) async {
      const branding = SoliplexBranding(
        accentLight: Colors.blue,
        accentDark: Colors.indigo,
        appName: 'X',
        logoLight: lightLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(branding: branding), brightness: Brightness.dark),
      );
      expect(find.text('LIGHT'), findsOneWidget);
      expect(find.byType(SoliplexGlow), findsOneWidget);
    });

    testWidgets('dark fallback halo is derived from the theme onSurface',
        (tester) async {
      const branding = SoliplexBranding(
        accentLight: Colors.blue,
        accentDark: Colors.indigo,
        appName: 'X',
        logoLight: lightLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(branding: branding), brightness: Brightness.dark),
      );
      final glow = tester.widget<SoliplexGlow>(find.byType(SoliplexGlow));
      expect(glow.color, ThemeData.dark().colorScheme.onSurface.withAlpha(179));
    });

    testWidgets('explicit logoGlow overrides the derived halo', (tester) async {
      const branding = SoliplexBranding(
        accentLight: Colors.blue,
        accentDark: Colors.indigo,
        appName: 'X',
        logoLight: lightLogo,
        logoGlow: Color(0xFF00FF00),
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(branding: branding), brightness: Brightness.dark),
      );
      final glow = tester.widget<SoliplexGlow>(find.byType(SoliplexGlow));
      expect(glow.color, const Color(0xFF00FF00));
    });
  });

  group('SoliplexBranding.soliplex', () {
    test('default branding carries the Soliplex identity', () {
      final brand = SoliplexBranding.soliplex;
      expect(brand.appName, 'Soliplex');
      expect(brand.accentLight, lightSoliplexColors.primary);
      expect(brand.accentDark, darkSoliplexColors.primary);
      expect(brand.logoDark, isNull);
    });
  });
}
