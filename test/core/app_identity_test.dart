import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/core/app_identity.dart';

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
      const identity = AppIdentity(
        appName: 'X',
        logoLight: lightLogo,
        logoDark: darkLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(identity: identity), brightness: Brightness.light),
      );
      expect(find.text('LIGHT'), findsOneWidget);
      expect(find.text('DARK'), findsNothing);
      expect(find.byType(SoliplexGlow), findsNothing);
    });

    testWidgets('dark mode prefers logoDark when provided', (tester) async {
      const identity = AppIdentity(
        appName: 'X',
        logoLight: lightLogo,
        logoDark: darkLogo,
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(identity: identity), brightness: Brightness.dark),
      );
      expect(find.text('DARK'), findsOneWidget);
      expect(find.byType(SoliplexGlow), findsNothing);
    });

    testWidgets('dark mode wraps logoLight in SoliplexGlow when no logoDark',
        (tester) async {
      const identity = AppIdentity(appName: 'X', logoLight: lightLogo);
      await tester.pumpWidget(
        wrap(const BrandLogo(identity: identity), brightness: Brightness.dark),
      );
      expect(find.text('LIGHT'), findsOneWidget);
      expect(find.byType(SoliplexGlow), findsOneWidget);
    });

    testWidgets('dark fallback halo is derived from the theme onSurface',
        (tester) async {
      const identity = AppIdentity(appName: 'X', logoLight: lightLogo);
      await tester.pumpWidget(
        wrap(const BrandLogo(identity: identity), brightness: Brightness.dark),
      );
      final glow = tester.widget<SoliplexGlow>(find.byType(SoliplexGlow));
      expect(glow.color, ThemeData.dark().colorScheme.onSurface.withAlpha(179));
    });

    testWidgets('explicit logoGlow overrides the derived halo', (tester) async {
      const identity = AppIdentity(
        appName: 'X',
        logoLight: lightLogo,
        logoGlow: Color(0xFF00FF00),
      );
      await tester.pumpWidget(
        wrap(const BrandLogo(identity: identity), brightness: Brightness.dark),
      );
      final glow = tester.widget<SoliplexGlow>(find.byType(SoliplexGlow));
      expect(glow.color, const Color(0xFF00FF00));
    });
  });

  group('AppIdentity.soliplex', () {
    test('default identity carries the Soliplex name and a single logo', () {
      final identity = AppIdentity.soliplex;
      expect(identity.appName, 'Soliplex');
      expect(identity.logoDark, isNull);
    });
  });

  test('rejects setting both logoGlow and logoDark', () {
    expect(
      () => AppIdentity(
        appName: 'X',
        logoLight: const Text('L'),
        logoDark: const Text('D'),
        logoGlow: const Color(0xFF00FF00),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('rejects an empty appName', () {
    expect(
      () => AppIdentity(appName: '', logoLight: const Text('L')),
      throwsA(isA<AssertionError>()),
    );
  });
}
