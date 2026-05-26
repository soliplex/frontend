import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

Widget _captureIntent(BadgeIntent intent, ValueChanged<BuildContext> capture) {
  return MaterialApp(
    theme: soliplexLightTheme(),
    home: Builder(
      builder: (context) {
        capture(context);
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets('neutral pulls from SoliplexBadgeThemeData', (tester) async {
    late ({Color background, Color foreground}) pair;
    await tester.pumpWidget(
      _captureIntent(
        BadgeIntent.neutral,
        (ctx) => pair = badgeIntentColors(BadgeIntent.neutral, ctx),
      ),
    );
    final theme = SoliplexTheme.of(tester.element(find.byType(SizedBox)));
    expect(pair.background, theme.badgeTheme.background);
    expect(pair.foreground, theme.badgeTheme.textStyle.color);
  });

  testWidgets('danger uses errorContainer / onErrorContainer', (tester) async {
    late ({Color background, Color foreground}) pair;
    await tester.pumpWidget(
      _captureIntent(
        BadgeIntent.danger,
        (ctx) => pair = badgeIntentColors(BadgeIntent.danger, ctx),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(pair.background, scheme.errorContainer);
    expect(pair.foreground, scheme.onErrorContainer);
  });

  testWidgets('success uses successContainer / onSuccessContainer',
      (tester) async {
    late ({Color background, Color foreground}) pair;
    await tester.pumpWidget(
      _captureIntent(
        BadgeIntent.success,
        (ctx) => pair = badgeIntentColors(BadgeIntent.success, ctx),
      ),
    );
    final colors =
        SoliplexTheme.of(tester.element(find.byType(SizedBox))).colors;
    expect(pair.background, colors.successContainer);
    expect(pair.foreground, colors.onSuccessContainer);
  });

  testWidgets('info derives from SymbolicColors.info', (tester) async {
    late ({Color background, Color foreground}) pair;
    await tester.pumpWidget(
      _captureIntent(
        BadgeIntent.info,
        (ctx) => pair = badgeIntentColors(BadgeIntent.info, ctx),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(pair.foreground, scheme.info);
    expect(pair.background.a, closeTo(0.15, 0.001));
  });

  testWidgets('warning derives from SymbolicColors.warning', (tester) async {
    late ({Color background, Color foreground}) pair;
    await tester.pumpWidget(
      _captureIntent(
        BadgeIntent.warning,
        (ctx) => pair = badgeIntentColors(BadgeIntent.warning, ctx),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(pair.foreground, scheme.warning);
    expect(pair.background.a, closeTo(0.15, 0.001));
  });
}
