import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('SoliplexGlow', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(
        wrap(const SoliplexGlow(color: Colors.white, child: Text('MARK'))),
      );

      expect(find.text('MARK'), findsOneWidget);
    });

    testWidgets('takes exactly the child size — the glow bleeds outside layout',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const SoliplexGlow(
            color: Colors.white,
            child: SizedBox(width: 64, height: 40),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SoliplexGlow)), const Size(64, 40));
    });

    testWidgets('paints a circular radial gradient that fades to transparent',
        (tester) async {
      const color = Color(0xFF112233);
      await tester.pumpWidget(
        wrap(
          const SoliplexGlow(
            color: color,
            child: SizedBox(width: 32, height: 32),
          ),
        ),
      );

      final decoration = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byType(SoliplexGlow),
              matching: find.byType(DecoratedBox),
            ),
          )
          .decoration as BoxDecoration;

      expect(decoration.shape, BoxShape.circle);
      expect(decoration.gradient, isA<RadialGradient>());
      expect(
        (decoration.gradient! as RadialGradient).colors,
        [color, color.withAlpha(0)],
      );
    });

    testWidgets('extent controls how far the backplate bleeds past the child',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          const SoliplexGlow(
            color: Colors.white,
            extent: 24,
            child: SizedBox(width: 32, height: 32),
          ),
        ),
      );

      final positioned = tester.widget<Positioned>(
        find.descendant(
          of: find.byType(SoliplexGlow),
          matching: find.byType(Positioned),
        ),
      );

      expect(positioned.left, -24);
      expect(positioned.top, -24);
      expect(positioned.right, -24);
      expect(positioned.bottom, -24);
    });
  });
}
