import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/skill_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const fullSkill = RoomSkill(
    name: 'my-skill',
    description: 'Does cool things',
    source: 'filesystem',
    license: 'MIT',
    compatibility: '>=1.0.0',
    allowedTools: ['tool_a', 'tool_b'],
    stateNamespace: 'my_ns',
    metadata: {'author': 'Alice'},
  );

  const emptySkill = RoomSkill(name: 'empty-skill', description: '');

  group('SkillContentColumn', () {
    testWidgets('renders all skill fields', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(child: SkillContentColumn(skill: fullSkill)),
        ),
      );
      expect(find.text('description'), findsOneWidget);
      expect(find.text('Does cool things'), findsOneWidget);
      expect(find.text('source'), findsOneWidget);
      expect(find.text('filesystem'), findsOneWidget);
      expect(find.text('license'), findsOneWidget);
      expect(find.text('MIT'), findsOneWidget);
      expect(find.text('compatibility'), findsOneWidget);
      expect(find.text('>=1.0.0'), findsOneWidget);
      expect(find.text('allowed_tools'), findsOneWidget);
      expect(find.text('tool_a, tool_b'), findsOneWidget);
      expect(find.text('state_namespace'), findsOneWidget);
      expect(find.text('my_ns'), findsOneWidget);
    });

    testWidgets('shows None for empty or null fields', (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(child: SkillContentColumn(skill: emptySkill)),
        ),
      );
      // description is empty string → None
      // source, license, compatibility, allowedTools, stateNamespace are null → None
      expect(find.text('None'), findsWidgets);
    });

    testWidgets('Show more button appears when metadata is non-empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(child: SkillContentColumn(skill: fullSkill)),
        ),
      );
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('Show more button appears when stateTypeSchema is non-empty', (
      tester,
    ) async {
      const skillWithSchema = RoomSkill(
        name: 'schema-skill',
        description: 'Has schema',
        stateTypeSchema: {'type': 'object'},
      );
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: SkillContentColumn(skill: skillWithSchema),
          ),
        ),
      );
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('Show more button hidden when no metadata or schema', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(child: SkillContentColumn(skill: emptySkill)),
        ),
      );
      expect(find.text('Show more'), findsNothing);
    });
  });

  group('SkillDetailDialog', () {
    testWidgets('shows metadata entries', (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: fullSkill)));
      expect(find.text('Metadata'), findsOneWidget);
      expect(find.text('author'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows Empty for null stateTypeSchema', (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: fullSkill)));
      expect(find.text('State Schema'), findsOneWidget);
      // fullSkill has no stateTypeSchema → should show Empty
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('shows Empty for null metadata and schema', (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: emptySkill)));
      // Both sections are empty → two "Empty" labels
      expect(find.text('Empty'), findsNWidgets(2));
    });

    testWidgets('Close button dismisses dialog', (tester) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showDialog<void>(
                        context: context,
                        builder: (_) => SkillDetailDialog(skill: fullSkill),
                      ),
                  child: const Text('Open'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
