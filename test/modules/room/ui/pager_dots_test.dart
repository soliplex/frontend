import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/pager_dots.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders one CircleAvatar per item when itemCount <= maxVisible',
      (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 3,
      currentIndex: 1,
      onGoTo: (_) {},
    )));

    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });

  testWidgets('hides entirely when itemCount > maxVisible', (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 13,
      currentIndex: 0,
      maxVisible: 12,
      onGoTo: (_) {},
    )));

    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('still renders when itemCount equals maxVisible exactly',
      (tester) async {
    // Boundary at the cap — a regression to >= would silently hide
    // dots that should stay.
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 12,
      currentIndex: 0,
      maxVisible: 12,
      onGoTo: (_) {},
    )));

    expect(find.byType(CircleAvatar), findsNWidgets(12));
  });

  testWidgets('hides entirely for a single item', (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 1,
      currentIndex: 0,
      onGoTo: (_) {},
    )));

    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('active dot is visually distinguished from inactive dots',
      (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 3,
      currentIndex: 2,
      onGoTo: (_) {},
    )));

    final dots =
        tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
    final activeColor = dots[2].backgroundColor;
    final inactiveColor = dots[0].backgroundColor;
    expect(activeColor, isNot(equals(inactiveColor)));
    expect(dots[1].backgroundColor, equals(inactiveColor));
  });

  testWidgets('tapping a dot calls onGoTo with that index', (tester) async {
    var tappedIndex = -1;
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 3,
      currentIndex: 0,
      onGoTo: (i) => tappedIndex = i,
      labelForIndex: (i) => 'dot-$i',
    )));

    await tester.tap(find.byTooltip('dot-2'));
    expect(tappedIndex, 2);
  });

  testWidgets('renders without tooltips when labelForIndex is null',
      (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 3,
      currentIndex: 0,
      onGoTo: (_) {},
    )));

    expect(find.byType(Tooltip), findsNothing);
  });
}
