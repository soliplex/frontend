import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('SoliplexShimmer', () {
    Widget wrap(Widget child, {double width = 300}) => MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        );

    testWidgets('renders a CustomPaint', (tester) async {
      await tester.pumpWidget(wrap(const SoliplexShimmer()));

      expect(find.byType(SoliplexShimmer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SoliplexShimmer),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('fills the bounded width and sizes to the line metrics',
        (tester) async {
      await tester.pumpWidget(
        wrap(const SoliplexShimmer(lineFractions: [1, 1]), width: 240),
      );

      // Two bars at the default 14 height with one 12 (s3) gap → 40.
      expect(tester.getSize(find.byType(SoliplexShimmer)), const Size(240, 40));
    });

    testWidgets('line count and per-bar metrics drive the height',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const SoliplexShimmer(
            lineFractions: [1, 1, 1],
            lineHeight: 10,
            lineSpacing: 8,
          ),
        ),
      );

      // 3 * 10 + 2 * 8 = 46.
      expect(tester.getSize(find.byType(SoliplexShimmer)).height, 46);
    });

    testWidgets('keeps animating across frames without settling',
        (tester) async {
      await tester.pumpWidget(wrap(const SoliplexShimmer()));

      // The sweep repeats forever, so it must never settle — advancing time
      // just produces more frames.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SoliplexShimmer), findsOneWidget);
    });

    testWidgets('works without the brand theme extension', (tester) async {
      // A bare MaterialApp has no SoliplexTheme; the shimmer must still render.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 200, child: SoliplexShimmer())),
          ),
        ),
      );

      expect(find.byType(SoliplexShimmer), findsOneWidget);
    });
  });
}
