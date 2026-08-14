import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

ThemeData _configuredTheme() => soliplexLightTheme(
      classifications: ClassificationTheme(
        defaultId: 'public',
        levels: const [
          ClassificationLevel(
            id: 'public',
            label: 'PUBLIC',
            background: Color(0xFFDDEEDD),
            foreground: Color(0xFF114411),
          ),
          ClassificationLevel(
            id: 'restricted',
            label: 'RESTRICTED',
            background: Color(0xFFEEDDDD),
            foreground: Color(0xFF441111),
            icon: Icons.lock,
          ),
        ],
      ),
    );

/// A single line of the pill's label style, rounded up. Between this and the
/// 48px height the bar-presentation tests impose there is room to tell a
/// stretched label box from one that kept its own height.
const _naturalLabelHeight = 30.0;

/// The corner the pill was built with, read back off its painted decoration.
double _cornerOf(WidgetTester tester, Finder badge) {
  final container = tester.widget<Container>(
    find.descendant(of: badge, matching: find.byType(Container)),
  );
  final radius = (container.decoration! as BoxDecoration)
      .borderRadius!
      .resolve(TextDirection.ltr);
  return radius.topLeft.x;
}

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? _configuredTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders the resolved label and icon', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'restricted')),
    );
    expect(find.text('RESTRICTED'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('null resolves to the configured default', (tester) async {
    await tester.pumpWidget(_wrap(const SoliplexClassificationBadge()));
    expect(find.text('PUBLIC'), findsOneWidget);
  });

  testWidgets('exposes a Semantics classification label', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'restricted')),
    );
    expect(find.bySemanticsLabel('Classification: RESTRICTED'), findsOneWidget);
  });

  testWidgets('unknown id renders a fail-loud label carrying the id',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'bogus')),
    );
    expect(find.textContaining('bogus'), findsOneWidget);
  });

  testWidgets('hugs its label when the parent leaves the height open',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'restricted')),
    );
    expect(
      tester.getSize(find.byType(SoliplexClassificationBadge)).height,
      lessThan(48),
    );
  });

  testWidgets('an imposed height stretches the label box by default',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          height: 48,
          child: SoliplexClassificationBadge(classification: 'public'),
        ),
      ),
    );
    // The label is forced to the padded height and paints from its top edge —
    // the asymmetry the bar presentation fixes. Measure the label's box, not
    // its centre: a stretched box has the same centre as a centred one.
    expect(
      tester.getSize(find.text('PUBLIC')).height,
      greaterThan(_naturalLabelHeight),
    );
  });

  testWidgets(
      'the bar presentation fills the parent height and centres the '
      'label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          height: 48,
          child: SoliplexClassificationBadge.bar(classification: 'public'),
        ),
      ),
    );
    final badge = find.byType(SoliplexClassificationBadge);
    expect(tester.getSize(badge).height, 48);
    // Width still hugs the label — only the vertical axis is filled.
    expect(tester.getSize(badge).width, lessThan(200));
    // The label keeps its own height and sits centred in the pill.
    final label = find.text('PUBLIC');
    expect(tester.getSize(label).height, lessThan(_naturalLabelHeight));
    expect(
      tester.getCenter(label).dy,
      moreOrLessEquals(tester.getCenter(badge).dy, epsilon: 1),
    );
  });

  testWidgets(
      'the bar presentation takes the brand corner and roomier '
      'padding', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Column(
          children: [
            SoliplexClassificationBadge(classification: 'public'),
            SizedBox(
              height: 48,
              child: SoliplexClassificationBadge.bar(classification: 'public'),
            ),
          ],
        ),
      ),
    );
    final inline = find.byType(SoliplexClassificationBadge).first;
    final bar = find.byType(SoliplexClassificationBadge).last;
    final radii = SoliplexTheme.of(tester.element(bar)).radii;

    // The room avatars in the rail wear the same brand corner.
    expect(_cornerOf(tester, bar), radii.md);
    expect(_cornerOf(tester, inline), radii.sm);
    // Same label, doubled horizontal padding — 8px wider on each side.
    expect(
      tester.getSize(bar).width - tester.getSize(inline).width,
      2 * SoliplexSpacing.s2,
    );
  });

  testWidgets('renders nothing for the unconfigured built-in fallback',
      (tester) async {
    // Bare Material theme → ClassificationTheme.of falls back; the default
    // resolves to the neutral built-in, which is suppressed.
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(), theme: ThemeData()),
    );
    expect(find.text('UNMARKED'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Classification')), findsNothing);
  });
}
