import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_markings_row.dart';

ClassificationTheme _classifications() => ClassificationTheme(
      defaultId: 'internal',
      levels: const [
        ClassificationLevel(
          id: 'internal',
          label: 'INTERNAL',
          background: Colors.black12,
          foreground: Colors.black87,
        ),
      ],
    );

Widget _host(Widget child, {ClassificationTheme? classifications}) =>
    MaterialApp(
      theme: classifications == null
          ? null
          : soliplexLightTheme(classifications: classifications),
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
    );

void main() {
  group('roomHasVisibleMarkings', () {
    testWidgets('false for a plain room with no configured classification',
        (tester) async {
      late bool result;
      await tester.pumpWidget(_host(Builder(
        builder: (context) {
          result = roomHasVisibleMarkings(
            context,
            const Room(id: 'r1', name: 'General'),
          );
          return const SizedBox.shrink();
        },
      )));
      expect(result, isFalse);
    });

    testWidgets('true when the room has quizzes', (tester) async {
      late bool result;
      await tester.pumpWidget(_host(Builder(
        builder: (context) {
          result = roomHasVisibleMarkings(
            context,
            const Room(id: 'r1', name: 'General', quizzes: {'q1': 'Quiz'}),
          );
          return const SizedBox.shrink();
        },
      )));
      expect(result, isTrue);
    });

    testWidgets('true when a classification is configured', (tester) async {
      late bool result;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) {
            result = roomHasVisibleMarkings(
              context,
              const Room(id: 'r1', name: 'General'),
            );
            return const SizedBox.shrink();
          },
        ),
        classifications: _classifications(),
      ));
      expect(result, isTrue);
    });
  });

  group('RoomMarkingsRow', () {
    testWidgets('always mounts the classification badge as a seam',
        (tester) async {
      await tester.pumpWidget(
        _host(const RoomMarkingsRow(room: Room(id: 'r1', name: 'General'))),
      );
      // Present even with no classification configured (renders nothing), so
      // cards can rely on the seam being in the tree.
      expect(find.byType(SoliplexClassificationBadge), findsOneWidget);
    });

    testWidgets('shows the quiz indicator only when the room has quizzes',
        (tester) async {
      await tester.pumpWidget(
        _host(const RoomMarkingsRow(room: Room(id: 'r1', name: 'General'))),
      );
      expect(find.byIcon(Icons.quiz), findsNothing);

      await tester.pumpWidget(
        _host(const RoomMarkingsRow(
          room: Room(id: 'r1', name: 'General', quizzes: {'q1': 'Quiz'}),
        )),
      );
      expect(find.byIcon(Icons.quiz), findsOneWidget);
    });

    testWidgets('renders the configured marking label', (tester) async {
      await tester.pumpWidget(_host(
        const RoomMarkingsRow(room: Room(id: 'r1', name: 'General')),
        classifications: _classifications(),
      ));
      expect(find.text('INTERNAL'), findsOneWidget);
    });
  });
}
