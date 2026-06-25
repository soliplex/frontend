import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
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
}
