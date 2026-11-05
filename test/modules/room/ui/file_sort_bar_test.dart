import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_sort_bar.dart';

/// The files panel's content width on a 320 px screen: the panel's outer and
/// inner `s2` padding on both sides, and the `s3` scrollbar gutter.
const _panelContentWidth = 320.0 - 4 * SoliplexSpacing.s2 - SoliplexSpacing.s3;

Future<List<FileSortKey>> _pump(
  WidgetTester tester,
  FileSort sort, {
  bool hasTimes = true,
  bool hasSizes = true,
  // Wide enough that the test font, a full em per glyph, shows every
  // segment.
  double width = 600,
}) async {
  final taps = <FileSortKey>[];
  await tester.pumpWidget(MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: FileSortBar(
            sort: sort,
            hasTimes: hasTimes,
            hasSizes: hasSizes,
            onTap: taps.add,
          ),
        ),
      ),
    ),
  ));
  return taps;
}

void main() {
  testWidgets('Folders is the last segment', (tester) async {
    await _pump(tester, FileSort.foldersAToZ);

    final labels = ['Name', 'Modified', 'Size', 'Folders'];
    final lefts = [for (final l in labels) tester.getTopLeft(find.text(l)).dx];

    expect(lefts, [...lefts]..sort());
  });

  testWidgets('tapping an inactive segment reports it', (tester) async {
    final taps = await _pump(tester, FileSort.foldersAToZ);

    await tester.tap(find.text('Size'));

    expect(taps, [FileSortKey.size]);
  });

  testWidgets('tapping the active segment reports it', (tester) async {
    final taps = await _pump(tester, FileSort.foldersAToZ);

    await tester.tap(find.text('Folders'));

    expect(taps, [FileSortKey.folders]);
  });

  testWidgets('the active segment shows its direction', (tester) async {
    await _pump(tester, FileSort.largestFirst);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
    expect(find.bySemanticsLabel('Size, largest first'), findsOneWidget);

    await _pump(tester, FileSort.smallestFirst);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsNothing);
    expect(find.bySemanticsLabel('Size, smallest first'), findsOneWidget);
  });

  testWidgets('the active segment stands out from the others', (tester) async {
    await _pump(tester, FileSort.nameAToZ);
    final scheme =
        Theme.of(tester.element(find.byType(FileSortBar))).colorScheme;
    Color? colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;

    expect(colorOf('Name'), scheme.onPrimary);
    expect(colorOf('Folders'), scheme.onSurface);
  });

  testWidgets('an inactive segment says what a tap would select',
      (tester) async {
    await _pump(tester, FileSort.nameZToA);

    expect(find.bySemanticsLabel('Modified, newest first'), findsOneWidget);
    expect(find.byTooltip('Modified, newest first'), findsOneWidget);
  });

  testWidgets('a screen reader hears each description once', (tester) async {
    await _pump(tester, FileSort.largestFirst);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Size, largest first'))
        .getSemanticsData();

    expect(data.tooltip, isEmpty);
  });

  testWidgets('a screen reader or keyboard can operate a segment',
      (tester) async {
    await _pump(tester, FileSort.largestFirst);

    final data = tester
        .getSemantics(find.bySemanticsLabel('Name, A to Z'))
        .getSemanticsData();

    expect(data.hasAction(SemanticsAction.tap), isTrue);
    // Focusable: the flag is set either way, unlike on a node that cannot
    // take focus.
    expect(data.flagsCollection.isFocused.toBoolOrNull(), isNotNull);
  });

  testWidgets('a bar wider than the panel scrolls rather than shrinking',
      (tester) async {
    // The test font draws every glyph a full em wide, so this bar is wider
    // than the panel, as a large text scale or a wide brand font makes it.
    await _pump(tester, FileSort.newestFirst, width: 2000);
    final natural = tester.getRect(find.text('Modified')).width;

    await _pump(tester, FileSort.newestFirst, width: _panelContentWidth);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('Modified')).width, natural);
  });

  testWidgets('a server without times disables Modified', (tester) async {
    final taps = await _pump(tester, FileSort.nameAToZ, hasTimes: false);

    await tester.tap(find.text('Modified'), warnIfMissed: false);

    expect(taps, isEmpty);
    expect(
      find.bySemanticsLabel(
          'Modified: None of these files has a modified time'),
      findsOneWidget,
    );
    expect(find.byTooltip('None of these files has a modified time'),
        findsOneWidget);
  });

  testWidgets('a server without sizes disables Size', (tester) async {
    final taps = await _pump(tester, FileSort.nameAToZ, hasSizes: false);

    await tester.tap(find.text('Size'), warnIfMissed: false);

    expect(taps, isEmpty);
    expect(
      find.bySemanticsLabel('Size: None of these files has a size'),
      findsOneWidget,
    );
    expect(find.byTooltip('None of these files has a size'), findsOneWidget);
  });
}
