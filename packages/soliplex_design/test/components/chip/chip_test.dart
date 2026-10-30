import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
// Not exported from the barrel: the contrast floor a colored chip has to
// clear is the package's own guarantee, not a knob callers turn.
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
    testWidgets('washes and outlines the swatch rather than filling it', (
      tester,
    ) async {
      const swatch = Color(0xFF42D76D);
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(label: Text('Manuals'), color: swatch),
        ),
      );

      final tint = swatchTint(swatch, Brightness.light);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(tint.fill));
      expect(chip.side?.color, equals(tint.outline));

      // The point of the exercise: a label annotates a thread, so the
      // chip must not be painted at the strength the picker offered.
      expect(chip.backgroundColor!.a, lessThan(swatch.a));
    });

    testWidgets('desaturates a swatch chosen at full strength', (tester) async {
      // Users pick from a hue wheel, so swatches arrive fully committed
      // to their hue; a row of those out-shouts the threads it labels.
      const vivid = Color(0xFFFF0000);
      final tint = swatchTint(vivid, Brightness.light);

      expect(
        HSLColor.fromColor(tint.content).saturation,
        lessThan(HSLColor.fromColor(vivid).saturation),
      );
    });

    testWidgets('keeps the neutral swatch neutral', (tester) async {
      // Clamped, not scaled — an already-quiet swatch must come through
      // untouched, or an uncoloured label picks up a tint nobody chose.
      final tint = swatchTint(neutralSwatch, Brightness.light);
      expect(HSLColor.fromColor(tint.content).saturation, equals(0));
      expect(HSLColor.fromColor(tint.fill).saturation, equals(0));
    });

    testWidgets('derives a readable foreground on a pale swatch', (
      tester,
    ) async {
      // The caller never supplies the foreground — an open colour field
      // would otherwise invite white text on pale yellow.
      const pale = Color(0xFFF5F5A0);
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(label: Text('Manuals'), color: pale),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      final foreground = chip.labelStyle!.color!;
      expect(
        contrastRatio(foreground, soliplexLightTheme().colorScheme.surface),
        greaterThanOrEqualTo(minContrast),
      );
    });

    testWidgets('stays readable on a near-black swatch too', (tester) async {
      const deep = Color(0xFF1A1A2E);
      await tester.pumpWidget(
        _harness(
          const SoliplexChip.colored(label: Text('Archived'), color: deep),
        ),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(
        contrastRatio(
          chip.labelStyle!.color!,
          soliplexLightTheme().colorScheme.surface,
        ),
        greaterThanOrEqualTo(minContrast),
      );
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
      expect(
        chip.deleteIconColor,
        equals(swatchTint(swatch, Brightness.light).content),
      );

      await tester.tap(find.byIcon(Icons.cancel));
      expect(fired, 1);
    });
  });
}
