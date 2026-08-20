import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/home_shell.dart';

void main() {
  group('HomeShellHeader', () {
    testWidgets('app name renders in the brand font when configured',
        (tester) async {
      final theme = lowerBrandTheme(
        const BrandTheme.soliplex().copyWith(
          typography: const BrandTypography(brandFamily: 'Squada One'),
        ),
        Brightness.light,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: HomeShellHeader(appName: 'Soliplex'),
          ),
        ),
      );

      final nameText = tester.widget<Text>(find.text('Soliplex'));
      expect(nameText.style?.fontFamily, 'Squada One');
    });

    testWidgets('app name uses base text style when no brand font configured',
        (tester) async {
      final theme =
          lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: HomeShellHeader(appName: 'Soliplex'),
          ),
        ),
      );

      final nameText = tester.widget<Text>(find.text('Soliplex'));
      // No brand font: style comes from textTheme.titleSmall unmodified.
      expect(nameText.style?.fontFamily, isNot('Squada One'));
    });
  });

  group('HomeShellHeader utility menu', () {
    /// The header under a router, so the menu's destinations can be observed by
    /// where they navigate to.
    Future<GoRouter> pumpHeader(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: HomeShellHeader(appName: 'Soliplex'),
            ),
          ),
          GoRoute(
            path: AppRoutes.diagnostics,
            builder: (_, __) => const Text('diagnostics screen'),
          ),
          GoRoute(
            path: AppRoutes.versions,
            builder: (_, __) => const Text('versions screen'),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('reaches diagnostics, which needs no connected server',
        (tester) async {
      // The rail and sidebar menus both sit behind a connected server, so this
      // is the only route to the diagnostics screen for a user who cannot sign
      // in — which is when it is worth reading.
      await pumpHeader(tester);

      await tester.tap(find.byTooltip('Diagnostics & versions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();

      expect(find.text('diagnostics screen'), findsOneWidget);
    });

    testWidgets('reaches versions from the same menu', (tester) async {
      await pumpHeader(tester);

      await tester.tap(find.byTooltip('Diagnostics & versions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();

      expect(find.text('versions screen'), findsOneWidget);
    });

    testWidgets('is hidden on screens that are themselves destinations',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeShellHeader(appName: 'Soliplex', showUtilityMenu: false),
          ),
        ),
      );

      expect(find.byTooltip('Diagnostics & versions'), findsNothing);
    });
  });
}
