import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
// Not exported from the barrel: the derived foreground is an internal
// guarantee of 'SoliplexChip.colored', not something callers supply.
import 'package:soliplex_design/src/brand/contrast.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    theme: soliplexLightTheme(),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('SoliplexChip (display)', () {
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

    testWidgets('intent.danger paints errorContainer background', (
      tester,
    ) async {
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
  });

  group('SoliplexChip.colored', () {
    testWidgets('paints the colour it was given', (tester) async {
      const swatch = Color(0xFF42D76D);
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(label: Text('Manuals'), color: swatch),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(swatch));
    });

    testWidgets('derives a readable foreground on a light swatch', (
      tester,
    ) async {
      // Users pick label colours, so the caller never supplies the
      // foreground — an open colour field would otherwise invite white
      // text on pale yellow.
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(
            label: Text('Manuals'),
            color: Color(0xFFF5F5A0),
          ),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(
        chip.labelStyle?.color,
        equals(readableOn(const Color(0xFFF5F5A0))),
      );
    });

    testWidgets('flips the foreground on a dark swatch', (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(
            label: Text('Archived'),
            color: Color(0xFF1A1A2E),
          ),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      final onLight = readableOn(const Color(0xFFF5F5A0));
      expect(chip.labelStyle?.color, isNot(equals(onLight)));
    });

    testWidgets('onDeleted fires and the close icon matches the label', (
      tester,
    ) async {
      var fired = 0;
      const swatch = Color(0xFF42D76D);
      await tester.pumpWidget(
        _harness(
          SoliplexChip.colored(
            label: const Text('Manuals'),
            color: swatch,
            onDeleted: () => fired++,
          ),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.deleteIconColor, equals(readableOn(swatch)));

      await tester.tap(find.byIcon(Icons.cancel));
      expect(fired, 1);
    });
  });
}
