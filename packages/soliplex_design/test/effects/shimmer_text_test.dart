import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('SoliplexShimmerText', () {
    Widget wrap(Widget child) => MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('masks its child with a ShaderMask', (tester) async {
      await tester.pumpWidget(
        wrap(const SoliplexShimmerText(child: Text('Thinking'))),
      );

      expect(find.text('Thinking'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SoliplexShimmerText),
          matching: find.byType(ShaderMask),
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps animating across frames without settling',
        (tester) async {
      await tester.pumpWidget(
        wrap(const SoliplexShimmerText(child: Text('Generating response'))),
      );

      // The sweep repeats forever, so it must never settle — advancing time
      // just produces more frames.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SoliplexShimmerText), findsOneWidget);
    });

    testWidgets('works without the brand theme extension', (tester) async {
      // A bare MaterialApp has no SoliplexTheme; the shimmer must still render.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: SoliplexShimmerText(child: Text('Calling'))),
          ),
        ),
      );

      expect(find.byType(SoliplexShimmerText), findsOneWidget);
      expect(find.byType(ShaderMask), findsOneWidget);
    });
  });
}
