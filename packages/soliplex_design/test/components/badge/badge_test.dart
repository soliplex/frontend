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
  testWidgets(
    'intent.danger paints the errorContainer background',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const SoliplexBadge(
            label: Text('Blocked'),
            intent: BadgeIntent.danger,
          ),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      final scheme = soliplexLightTheme().colorScheme;
      expect(decoration.color, scheme.errorContainer);
    },
  );
}
