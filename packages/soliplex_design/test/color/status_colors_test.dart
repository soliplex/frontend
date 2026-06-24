import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

ThemeData _themeWithWarning(Color warning) => lowerBrandTheme(
      BrandTheme(
        light: const BrandTheme.soliplex().light.copyWith(warning: warning),
        dark: const BrandTheme.soliplex().dark,
      ),
      Brightness.light,
    );

const _errorContainer = Color(0xFF330007);
const _onErrorContainer = Color(0xFFFFE9EC);
const _successContainer = Color(0xFF062E12);
const _onSuccessContainer = Color(0xFFEAFBF0);
const _warningContainer = Color(0xFF3A2A05);
const _onWarningContainer = Color(0xFFFFF3D6);
const _infoContainer = Color(0xFF06122E);
const _onInfoContainer = Color(0xFFE9F1FF);

ThemeData _themeWithContainers() => lowerBrandTheme(
      BrandTheme(
        light: const BrandTheme.soliplex().light.copyWith(
              errorContainer: _errorContainer,
              onErrorContainer: _onErrorContainer,
              successContainer: _successContainer,
              onSuccessContainer: _onSuccessContainer,
              warningContainer: _warningContainer,
              onWarningContainer: _onWarningContainer,
              infoContainer: _infoContainer,
              onInfoContainer: _onInfoContainer,
            ),
        dark: const BrandTheme.soliplex().dark,
      ),
      Brightness.light,
    );

Future<T> _readUnder<T>(
  WidgetTester tester,
  ThemeData? theme,
  T Function(BuildContext) read,
) async {
  late T value;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          value = read(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return value;
}

void main() {
  group('SymbolicColors', () {
    testWidgets('reads status colors from the Soliplex tokens', (tester) async {
      const custom = Color(0xFF123456);
      final warning =
          await _readUnder(tester, _themeWithWarning(custom), (c) => c.warning);
      expect(warning, custom);
    });

    testWidgets('exposes all four status roles from the theme tokens',
        (tester) async {
      final theme = soliplexLightTheme();
      final roles = await _readUnder(
        tester,
        theme,
        (c) => (
          danger: c.danger,
          success: c.success,
          warning: c.warning,
          info: c.info,
        ),
      );
      expect(roles.danger, lightSoliplexColors.danger);
      expect(roles.success, lightSoliplexColors.success);
      expect(roles.warning, lightSoliplexColors.warning);
      expect(roles.info, lightSoliplexColors.info);
    });

    testWidgets('falls back to the default palette when unthemed',
        (tester) async {
      final danger = await _readUnder(tester, null, (c) => c.danger);
      expect(danger, lightSoliplexColors.danger);
    });
  });

  group('component intents read the brand status tokens', () {
    testWidgets('badge warning uses the brand warning-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => badgeIntentColors(BadgeIntent.warning, c),
      );
      expect(colors.background, _warningContainer);
      expect(colors.foreground, _onWarningContainer);
    });

    testWidgets('badge info uses the brand info-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => badgeIntentColors(BadgeIntent.info, c),
      );
      expect(colors.background, _infoContainer);
      expect(colors.foreground, _onInfoContainer);
    });

    testWidgets('chip warning uses the brand warning-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => chipIntentColors(ChipIntent.warning, c),
      );
      expect(colors.background, _warningContainer);
      expect(colors.foreground, _onWarningContainer);
    });

    testWidgets('chip info uses the brand info-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => chipIntentColors(ChipIntent.info, c),
      );
      expect(colors.background, _infoContainer);
      expect(colors.foreground, _onInfoContainer);
    });

    testWidgets('badge danger uses the brand error-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => badgeIntentColors(BadgeIntent.danger, c),
      );
      expect(colors.background, _errorContainer);
      expect(colors.foreground, _onErrorContainer);
    });

    testWidgets('badge success uses the brand success-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => badgeIntentColors(BadgeIntent.success, c),
      );
      expect(colors.background, _successContainer);
      expect(colors.foreground, _onSuccessContainer);
    });

    testWidgets('chip danger uses the brand error-container tokens',
        (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithContainers(),
        (c) => chipIntentColors(ChipIntent.danger, c),
      );
      expect(colors.background, _errorContainer);
      expect(colors.foreground, _onErrorContainer);
    });
  });
}
