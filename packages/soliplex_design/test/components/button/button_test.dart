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
  group('SoliplexButton.filled', () {
    testWidgets('fires onPressed on tap', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () => fired++,
            child: const Text('Save'),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      expect(fired, 1);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexButton.filled(
            onPressed: null,
            child: Text('Save'),
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );
    });

    testWidgets('intent.danger paints the error background', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () {},
            intent: ButtonIntent.danger,
            child: const Text('Delete'),
          ),
        ),
      );
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      final scheme = soliplexLightTheme().colorScheme;
      final bg = filled.style!.backgroundColor!.resolve(<WidgetState>{});
      expect(bg, scheme.error);
    });

    testWidgets('isLoading blocks taps and shows a spinner', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () => fired++,
            isLoading: true,
            child: const Text('Save'),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      expect(fired, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('icon + isLoading swaps the icon for a spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () {},
            icon: const Icon(Icons.add),
            isLoading: true,
            child: const Text('Add'),
          ),
        ),
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('iconAlignment.end renders the icon after the label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () {},
            icon: const Icon(Icons.arrow_forward),
            iconAlignment: IconAlignment.end,
            child: const Text('Next'),
          ),
        ),
      );
      final iconX = tester.getCenter(find.byIcon(Icons.arrow_forward)).dx;
      final labelX = tester.getCenter(find.text('Next')).dx;
      expect(iconX, greaterThan(labelX));
    });
  });

  group('SoliplexButton.outlined', () {
    testWidgets('intent.danger tints foreground with scheme.error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.outlined(
            onPressed: () {},
            intent: ButtonIntent.danger,
            child: const Text('Remove'),
          ),
        ),
      );
      final btn = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final scheme = soliplexLightTheme().colorScheme;
      final fg = btn.style!.foregroundColor!.resolve(<WidgetState>{});
      expect(fg, scheme.error);
    });
  });

  group('SoliplexButton.text', () {
    testWidgets('isCompact applies compact visual density', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.text(
            onPressed: () {},
            isCompact: true,
            child: const Text('Lobby'),
          ),
        ),
      );
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      final density = btn.style!.visualDensity;
      expect(density, VisualDensity.compact);
    });

    testWidgets('alignment threads through to the button style', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.text(
            onPressed: () {},
            alignment: Alignment.centerLeft,
            child: const Text('Room info'),
          ),
        ),
      );
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      expect(btn.style!.alignment?.resolve(null), Alignment.centerLeft);
    });

    testWidgets('left-aligned full-width button hugs the leading edge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          SizedBox(
            width: 300,
            child: SoliplexButton.text(
              onPressed: () {},
              alignment: Alignment.centerLeft,
              child: const Text('Room info'),
            ),
          ),
        ),
      );
      // The label sits left of the 300-px box's centre when left-aligned.
      final labelX = tester.getCenter(find.text('Room info')).dx;
      final boxCentreX = tester.getCenter(find.byType(SizedBox).first).dx;
      expect(labelX, lessThan(boxCentreX));
    });
  });
}
