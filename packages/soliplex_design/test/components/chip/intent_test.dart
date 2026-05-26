import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

Widget _capture(ValueChanged<BuildContext> capture) {
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
  testWidgets('neutral returns nulls so Material theme defaults apply',
      (tester) async {
    late ({Color? background, Color? foreground}) pair;
    await tester.pumpWidget(
      _capture((ctx) => pair = chipIntentColors(ChipIntent.neutral, ctx)),
    );
    expect(pair.background, isNull);
    expect(pair.foreground, isNull);
  });

  testWidgets('danger uses errorContainer / onErrorContainer', (tester) async {
    late ({Color? background, Color? foreground}) pair;
    await tester.pumpWidget(
      _capture((ctx) => pair = chipIntentColors(ChipIntent.danger, ctx)),
    );
    final scheme = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(pair.background, scheme.errorContainer);
    expect(pair.foreground, scheme.onErrorContainer);
  });

  testWidgets('success uses successContainer / onSuccessContainer',
      (tester) async {
    late ({Color? background, Color? foreground}) pair;
    await tester.pumpWidget(
      _capture((ctx) => pair = chipIntentColors(ChipIntent.success, ctx)),
    );
    final colors =
        SoliplexTheme.of(tester.element(find.byType(SizedBox))).colors;
    expect(pair.background, colors.successContainer);
    expect(pair.foreground, colors.onSuccessContainer);
  });
}
