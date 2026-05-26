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

    testWidgets('icon variant uses FilledButton.icon', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.filled(
            onPressed: () {},
            icon: const Icon(Icons.add),
            child: const Text('Add'),
          ),
        ),
      );
      // FilledButton.icon still builds a FilledButton; presence of the
      // leading icon is what we verify.
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('icon + isLoading swaps the icon for a spinner',
        (tester) async {
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
  });

  group('SoliplexButton.outlined', () {
    testWidgets('renders an OutlinedButton', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.outlined(
            onPressed: () {},
            child: const Text('Cancel'),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('intent.danger tints foreground with scheme.error',
        (tester) async {
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
    testWidgets('renders a TextButton', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.text(
            onPressed: () {},
            child: const Text('More'),
          ),
        ),
      );
      expect(find.byType(TextButton), findsOneWidget);
    });

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

    testWidgets('isCompact false uses default density', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexButton.text(
            onPressed: () {},
            child: const Text('Lobby'),
          ),
        ),
      );
      final btn = tester.widget<TextButton>(find.byType(TextButton));
      // When isCompact is false the style does not assert a visualDensity,
      // so it stays null (the theme/default fills it in).
      expect(btn.style!.visualDensity, isNull);
    });
  });
}
