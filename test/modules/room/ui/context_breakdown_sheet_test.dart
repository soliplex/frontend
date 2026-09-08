import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/context_breakdown_sheet.dart';

/// WCAG relative-luminance contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

const _themes = <String, ThemeData Function()>{
  'light': soliplexLightTheme,
  'dark': soliplexDarkTheme,
};

const _usage = ContextUsage(
  tokens: 244,
  byKind: {
    SegmentKind.overhead: 180,
    SegmentKind.assistantText: 44,
    SegmentKind.userText: 20,
  },
  contextWindow: 32768,
  isProvisional: false,
  isExact: true,
);

Future<void> _pumpDialog(
  WidgetTester tester,
  ThemeData theme, {
  ContextUsage usage = _usage,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: ContextBreakdownDialog(usage: usage)),
    ),
  );
}

void main() {
  group('the categorical palette', () {
    _themes.forEach((name, build) {
      testWidgets('is legible against the $name surface', (tester) async {
        late Map<SegmentKind, Color> palette;
        late Color surface;

        await tester.pumpWidget(
          MaterialApp(
            theme: build(),
            home: Builder(
              builder: (context) {
                palette = categoricalColors(context);
                surface = Theme.of(context).colorScheme.surface;
                return const SizedBox();
              },
            ),
          ),
        );

        for (final entry in palette.entries) {
          // 1.4.11: a graphical object carrying meaning needs 3:1. A
          // wedge nobody can pick out says nothing.
          expect(
            contrast(entry.value, surface),
            greaterThanOrEqualTo(3.0),
            reason: '${entry.key.name} is too close to the $name surface',
          );
        }
      });

      testWidgets('gives every kind its own colour in $name', (tester) async {
        late Map<SegmentKind, Color> palette;

        await tester.pumpWidget(
          MaterialApp(
            theme: build(),
            home: Builder(
              builder: (context) {
                palette = categoricalColors(context);
                return const SizedBox();
              },
            ),
          ),
        );

        // Two kinds sharing a colour is worse than an ugly palette: the
        // chart then says two different things with one wedge.
        expect(palette.values.toSet(), hasLength(palette.length));
      });

      testWidgets('uses no neutral for a category in $name', (tester) async {
        late Map<SegmentKind, Color> palette;

        await tester.pumpWidget(
          MaterialApp(
            theme: build(),
            home: Builder(
              builder: (context) {
                palette = categoricalColors(context);
                return const SizedBox();
              },
            ),
          ),
        );

        for (final entry in palette.entries) {
          expect(
            HSLColor.fromColor(entry.value).saturation,
            greaterThan(0.25),
            reason: '${entry.key.name} reads as a grey',
          );
        }
      });

      testWidgets('separates free space from the $name surface',
          (tester) async {
        late Color free;
        late Color surface;
        late Map<SegmentKind, Color> palette;

        await tester.pumpWidget(
          MaterialApp(
            theme: build(),
            home: Builder(
              builder: (context) {
                free = freeSpaceColor(context);
                surface = Theme.of(context).colorScheme.surface;
                palette = categoricalColors(context);
                return const SizedBox();
              },
            ),
          ),
        );

        // The unused part has to read as a band, not as a hole in the
        // ring where the dialog shows through.
        expect(contrast(free, surface), greaterThan(1.8));
        expect(palette.values, isNot(contains(free)));
      });
    });
  });

  group('the scope toggle', () {
    testWidgets('sits beside the percentage', (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      expect(find.textContaining('% of 32768'), findsOneWidget);
      expect(find.byType(SegmentedButton<ContextChartScope>), findsOneWidget);
    });

    testWidgets('opens on the whole window', (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      final button = tester.widget<SegmentedButton<ContextChartScope>>(
        find.byType(SegmentedButton<ContextChartScope>),
      );

      expect(button.selected, {ContextChartScope.full});
      // The unused part of the window is a slice of its own.
      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('drops the unused wedge when switched to used', (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      await tester.tap(find.text('Used'));
      await tester.pumpAndSettle();

      expect(find.text('Free'), findsNothing);
      expect(find.text('Room overhead'), findsOneWidget);
    });

    testWidgets('is absent without a window to be a fraction of',
        (tester) async {
      // Nothing to choose between: both views would draw the same ring.
      await _pumpDialog(
        tester,
        soliplexLightTheme(),
        usage: const ContextUsage(
          tokens: 244,
          byKind: {SegmentKind.overhead: 244},
          isProvisional: false,
          isExact: true,
        ),
      );

      expect(find.byType(SegmentedButton<ContextChartScope>), findsNothing);
      expect(find.text('Free'), findsNothing);
    });
  });

  group('the chart', () {
    List<PieChartSectionData> sectionsOf(WidgetTester tester) {
      final chart = tester.widget<PieChart>(find.byType(PieChart));
      return chart.data.sections;
    }

    testWidgets('draws a wedge per category plus the unused part',
        (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      final sections = sectionsOf(tester);

      expect(sections, hasLength(4));
      expect(
        sections.map((s) => s.value).reduce((a, b) => a + b),
        // The wedges account for the whole window, not just what is in
        // use, which is what makes the ring readable as occupancy.
        closeTo(32768, 0.5),
      );
    });

    testWidgets('drops the unused wedge in the used view', (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      await tester.tap(find.text('Used'));
      await tester.pumpAndSettle();

      final sections = sectionsOf(tester);

      expect(sections, hasLength(3));
      expect(
        sections.map((s) => s.value).reduce((a, b) => a + b),
        closeTo(244, 0.5),
      );
    });

    testWidgets('paints each wedge its category colour', (tester) async {
      late Map<SegmentKind, Color> palette;
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Builder(
            builder: (context) {
              palette = categoricalColors(context);
              return const Scaffold(
                body: ContextBreakdownDialog(usage: _usage),
              );
            },
          ),
        ),
      );

      final colors = sectionsOf(tester).map((s) => s.color).toSet();

      expect(colors, contains(palette[SegmentKind.overhead]));
      expect(colors, contains(palette[SegmentKind.userText]));
      expect(colors, contains(palette[SegmentKind.assistantText]));
    });
  });

  group('the legend', () {
    testWidgets('lays out across the dialog rather than down it',
        (tester) async {
      await _pumpDialog(tester, soliplexLightTheme());

      expect(find.byType(Wrap), findsWidgets);
      expect(find.text('Room overhead'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
    });

    testWidgets('says nothing has been counted when it has not',
        (tester) async {
      await _pumpDialog(
        tester,
        soliplexLightTheme(),
        usage: const ContextUsage.unknown(),
      );

      expect(find.text('Nothing counted yet.'), findsOneWidget);
      expect(find.byType(SegmentedButton<ContextChartScope>), findsNothing);
    });
  });
}
