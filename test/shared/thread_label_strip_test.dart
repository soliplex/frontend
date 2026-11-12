import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/label_chip.dart';

ThreadLabel _label(int id, String name) =>
    ThreadLabel(id: id, name: name, color: '#42D76D');

Future<void> _pump(
  WidgetTester tester,
  List<ThreadLabel> labels, {
  double width = 400,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: ThreadLabelStrip(labels: labels),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ThreadLabelStrip', () {
    testWidgets('draws nothing for a thread with no labels', (tester) async {
      await _pump(tester, const []);

      expect(find.byType(SoliplexChip), findsNothing);
      expect(
        tester.getSize(find.byType(ThreadLabelStrip)).height,
        equals(0),
      );
    });

    testWidgets('folds labels past the third into "+N"', (tester) async {
      await _pump(tester, [
        _label(1, 'Archived'),
        _label(2, 'Backlog'),
        _label(3, 'Manuals'),
        _label(4, 'Q4 Roadmap'),
        _label(5, 'Urgent'),
      ]);

      expect(find.byType(SoliplexChip), findsNWidgets(3));
      expect(find.text('Q4 Roadmap'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('shows no "+N" when every label fits', (tester) async {
      await _pump(tester, [_label(1, 'Archived'), _label(2, 'Backlog')]);

      expect(find.byType(SoliplexChip), findsNWidgets(2));
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('stays on one line in a narrow sidebar', (tester) async {
      // Long names in a narrow column ellipsize rather than overflow.
      await _pump(
        tester,
        [
          _label(1, 'A very long label name indeed'),
          _label(2, 'Another long label name'),
          _label(3, 'And a third long one'),
          _label(4, 'Urgent'),
        ],
        width: 160,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('reads every label out as one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, [
        _label(1, 'Archived'),
        _label(2, 'Backlog'),
        _label(3, 'Manuals'),
        _label(4, 'Urgent'),
      ]);

      // Including the label folded into "+1", which sighted users can
      // find in the properties but a screen reader would never reach.
      expect(
        find.bySemanticsLabel('Labels: Archived, Backlog, Manuals, Urgent'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
