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

  testWidgets('hides entirely for a single item', (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 1,
      currentIndex: 0,
      onGoTo: (_) {},
    )));

    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('active dot uses primary, others use onSurfaceVariant @ 30%',
      (tester) async {
    await tester.pumpWidget(_wrap(PagerDots(
      itemCount: 3,
      currentIndex: 2,
      onGoTo: (_) {},
    )));

    final dots =
        tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
    final theme = ThemeData();
    final inactive = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3);
    expect(dots[0].backgroundColor, equals(inactive));
    expect(dots[1].backgroundColor, equals(inactive));
    expect(dots[2].backgroundColor, equals(theme.colorScheme.primary));
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
