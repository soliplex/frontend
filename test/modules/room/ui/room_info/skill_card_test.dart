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
    stateNamespace: 'my_ns',
    extraParameters: {'chunk_size': 512},
  );

  const emptySkill = RoomSkill(
    name: 'empty-skill',
    description: '',
  );

  group('SkillContentColumn', () {
    testWidgets('renders all skill fields', (tester) async {
      await tester.pumpWidget(wrap(
        SingleChildScrollView(child: SkillContentColumn(skill: fullSkill)),
      ));
      expect(find.text('description'), findsOneWidget);
      expect(find.text('Does cool things'), findsOneWidget);
      expect(find.text('source'), findsOneWidget);
      expect(find.text('filesystem'), findsOneWidget);
      expect(find.text('state_namespace'), findsOneWidget);
      expect(find.text('my_ns'), findsOneWidget);
    });

    testWidgets('shows None for empty or null fields', (tester) async {
      await tester.pumpWidget(wrap(
        SingleChildScrollView(child: SkillContentColumn(skill: emptySkill)),
      ));
      // description is an empty string, source and stateNamespace are null.
      // The count is exact so that deleting a row fails this test.
      expect(find.text('None'), findsNWidgets(3));
    });

    testWidgets('Show more button appears when extraParameters is non-empty',
        (tester) async {
      await tester.pumpWidget(wrap(
        SingleChildScrollView(child: SkillContentColumn(skill: fullSkill)),
      ));
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('Show more button appears when stateTypeSchema is non-empty',
        (tester) async {
      const skillWithSchema = RoomSkill(
        name: 'schema-skill',
        description: 'Has schema',
        stateTypeSchema: {'type': 'object'},
      );
      await tester.pumpWidget(wrap(
        SingleChildScrollView(
            child: SkillContentColumn(skill: skillWithSchema)),
      ));
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('Show more button hidden when no extraParameters or schema',
        (tester) async {
      await tester.pumpWidget(wrap(
        SingleChildScrollView(child: SkillContentColumn(skill: emptySkill)),
      ));
      expect(find.text('Show more'), findsNothing);
    });
  });

  group('SkillDetailDialog', () {
    testWidgets('shows extra parameter entries', (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: fullSkill)));
      expect(find.text('Extra Parameters'), findsOneWidget);
      expect(find.text('chunk_size'), findsOneWidget);
      expect(find.text('512'), findsOneWidget);
    });

    testWidgets('shows Empty for null stateTypeSchema', (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: fullSkill)));
      expect(find.text('State Schema'), findsOneWidget);
      // fullSkill has no stateTypeSchema → should show Empty
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('shows Empty for absent extraParameters and schema',
        (tester) async {
      await tester.pumpWidget(wrap(SkillDetailDialog(skill: emptySkill)));
      // Both sections are empty → two "Empty" labels
      expect(find.text('Empty'), findsNWidgets(2));
    });

    testWidgets('Close button dismisses dialog', (tester) async {
      await tester.pumpWidget(wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SkillDetailDialog(skill: fullSkill),
            ),
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
