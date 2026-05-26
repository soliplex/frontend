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
  group('SoliplexChip (display)', () {
    testWidgets('renders the label', (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexChip(label: Text('Draft'))),
      );
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('renders optional leading icon', (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexChip(
            label: Text('Synced'),
            icon: Icon(Icons.check),
          ),
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('onDeleted fires when close button tapped', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _harness(
          SoliplexChip(label: const Text('Tag'), onDeleted: () => fired++),
        ),
      );
      await tester.tap(find.byIcon(Icons.cancel));
      expect(fired, 1);
    });

    testWidgets('intent.danger paints errorContainer background',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexChip(
            label: Text('Blocked'),
            intent: ChipIntent.danger,
          ),
        ),
      );
      final chip = tester.widget<Chip>(find.byType(Chip));
      final scheme = soliplexLightTheme().colorScheme;
      expect(chip.backgroundColor, scheme.errorContainer);
    });
  });

  group('SoliplexChip.action', () {
    testWidgets('onPressed fires on tap', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _harness(
          SoliplexChip.action(
            label: const Text('Retry'),
            onPressed: () => fired++,
          ),
        ),
      );
      await tester.tap(find.text('Retry'));
      expect(fired, 1);
    });

    testWidgets('builds an ActionChip', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexChip.action(label: const Text('Retry'), onPressed: () {}),
        ),
      );
      expect(find.byType(ActionChip), findsOneWidget);
    });
  });

  group('SoliplexChip.filter', () {
    testWidgets('toggles selected via onSelected', (tester) async {
      var current = false;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => _harness(
            SoliplexChip.filter(
              label: const Text('All'),
              selected: current,
              onSelected: (v) => setState(() => current = v),
            ),
          ),
        ),
      );
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(current, isTrue);
    });

    testWidgets('builds a FilterChip', (tester) async {
      await tester.pumpWidget(
        _harness(
          SoliplexChip.filter(
            label: const Text('All'),
            selected: false,
            onSelected: (_) {},
          ),
        ),
      );
      expect(find.byType(FilterChip), findsOneWidget);
    });
  });
}
