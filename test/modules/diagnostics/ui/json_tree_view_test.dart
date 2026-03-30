import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/json_tree_model.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/json_tree_view.dart';

void main() {
  group('JsonTreeView', () {
    testWidgets('shows empty state for empty node list', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: [])),
        ),
      );
      expect(find.text('(empty)'), findsOneWidget);
    });

    testWidgets('shows value node text inline', (tester) async {
      const nodes = [ValueNode(key: 'name', value: 'Alice')];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );
      expect(find.textContaining('Alice'), findsOneWidget);
    });

    testWidgets('object node starts expanded and can be collapsed',
        (tester) async {
      final nodes = [
        ObjectNode(
          key: 'user',
          children: [const ValueNode(key: 'id', value: '1')],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );

      // Initially expanded: child value visible
      expect(find.textContaining('1'), findsOneWidget);

      // Tap the expandable header to collapse
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();

      // After collapse, child is hidden
      expect(find.textContaining('1'), findsNothing);
    });

    testWidgets('array node shows item count in collapsed label',
        (tester) async {
      final nodes = [
        ArrayNode(
          key: 'items',
          itemCount: 3,
          children: [
            const ValueNode(key: '[0]', value: 'a'),
            const ValueNode(key: '[1]', value: 'b'),
            const ValueNode(key: '[2]', value: 'c'),
          ],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: JsonTreeView(nodes: nodes)),
        ),
      );

      // Collapse the array
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await tester.pump();

      // Collapsed label includes item count
      expect(find.textContaining('[3]'), findsOneWidget);
    });
  });
}
