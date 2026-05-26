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
  testWidgets('renders the label', (tester) async {
    await tester.pumpWidget(_harness(
      const SoliplexBadge(label: Text('v2')),
    ),);
    expect(find.text('v2'), findsOneWidget);
  });

  testWidgets('renders the optional leading icon', (tester) async {
    await tester.pumpWidget(_harness(
      const SoliplexBadge(label: Text('Synced'), icon: Icon(Icons.check)),
    ),);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('intent.danger paints the errorContainer background',
      (tester) async {
    await tester.pumpWidget(_harness(
      const SoliplexBadge(label: Text('Blocked'), intent: BadgeIntent.danger),
    ),);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration! as BoxDecoration;
    final scheme = soliplexLightTheme().colorScheme;
    expect(decoration.color, scheme.errorContainer);
  });

  testWidgets('rounds to radii.sm', (tester) async {
    await tester.pumpWidget(_harness(
      const SoliplexBadge(label: Text('v2')),
    ),);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration! as BoxDecoration;
    final radius = decoration.borderRadius! as BorderRadius;
    expect(radius.topLeft.x, soliplexRadii.sm);
  });
}
