import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    theme: soliplexLightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('SoliplexMarkingBadge', () {
    testWidgets('renders the authoritative label text', (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexMarkingBadge(marking: DatasetMarking.cui)),
      );
      expect(find.text('CUI'), findsOneWidget);
    });

    testWidgets('portion variant renders the parenthesised mark',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexMarkingBadge.portion(marking: DatasetMarking.secret),
        ),
      );
      expect(find.text('(S)'), findsOneWidget);
    });

    testWidgets('paints the fixed marking background', (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexMarkingBadge(marking: DatasetMarking.unclassified),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF007A33));
    });

    testWidgets('exposes the marking to screen readers', (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexMarkingBadge(marking: DatasetMarking.cui)),
      );
      expect(
        find.bySemanticsLabel('Classification marking: CUI'),
        findsOneWidget,
      );
    });

    testWidgets('honours a white-label marking palette from the theme',
        (tester) async {
      const custom = Color(0xFF112233);
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(
            markingColors: SoliplexMarkingColors.dod.copyWith(
              cui: const SoliplexMarkingColor(
                background: custom,
                foreground: Color(0xFFFFFFFF),
              ),
            ),
          ),
          home: const Scaffold(
            body: Center(
              child: SoliplexMarkingBadge(marking: DatasetMarking.cui),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      expect((container.decoration! as BoxDecoration).color, custom);
    });
  });

  group('SoliplexMarkingBanner', () {
    testWidgets('renders the label and announces it as a header',
        (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexMarkingBanner(marking: DatasetMarking.cui)),
      );
      expect(find.text('CUI'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Classification banner: CUI'),
        findsOneWidget,
      );
    });
  });
}
