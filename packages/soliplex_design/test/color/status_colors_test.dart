import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_design/src/brand/brand_lowering.dart';

ThemeData _themeWithWarning(Color warning) => lower(
      BrandTheme(
        light: const BrandTheme.soliplex().light.copyWith(warning: warning),
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
    const custom = Color(0xFF123456);

    testWidgets('badge warning uses the brand warning token', (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithWarning(custom),
        (c) => badgeIntentColors(BadgeIntent.warning, c),
      );
      expect(colors.foreground, custom);
      expect(colors.background, custom.withValues(alpha: 0.15));
    });

    testWidgets('chip warning uses the brand warning token', (tester) async {
      final colors = await _readUnder(
        tester,
        _themeWithWarning(custom),
        (c) => chipIntentColors(ChipIntent.warning, c),
      );
      expect(colors.foreground, custom);
      expect(colors.background, custom.withValues(alpha: 0.15));
    });
  });
}
