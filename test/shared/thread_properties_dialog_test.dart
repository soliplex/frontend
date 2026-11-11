import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Signal;
import 'package:soliplex_client/soliplex_client.dart'
    show ThreadInfo, ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart' show soliplexLightTheme;
import 'package:soliplex_frontend/src/shared/thread_properties_dialog.dart';

const _manuals = ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D');
const _urgent = ThreadLabel(id: 2, name: 'Urgent', color: '#D93025');

/// What the dialog last asked to save.
class _Saves {
  final List<List<int>> labelIds = [];
  String? Function() answer = () => null;
}

Future<_Saves> _open(
  WidgetTester tester, {
  required ThreadInfo thread,
  List<ThreadLabel> catalogue = const [_manuals, _urgent],
}) async {
  final saves = _Saves();
  await tester.pumpWidget(
    MaterialApp(
      theme: soliplexLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ThreadPropertiesDialog(
                thread: thread,
                labels: Signal(catalogue),
                onSave: ({
                  required name,
                  required description,
                  required labelIds,
                }) async {
                  saves.labelIds.add(labelIds);
                  return saves.answer();
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saves;
}

ThreadInfo _thread({List<ThreadLabel> labels = const []}) => ThreadInfo(
      id: 't1',
      roomId: 'r1',
      name: 'Alpha',
      createdAt: DateTime.utc(2026),
      labels: labels,
    );

Finder get _save => find.widgetWithText(TextButton, 'Save');

void main() {
  group('ThreadPropertiesDialog', () {
    testWidgets('a blank name disables Save', (tester) async {
      await _open(tester, thread: _thread());

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pump();

      expect(tester.widget<TextButton>(_save).onPressed, isNull);
    });

    testWidgets('detaches a label the thread carries', (tester) async {
      final saves = await _open(tester, thread: _thread(labels: [_manuals]));

      await tester.tap(find.text('Manuals'));
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(saves.labelIds.single, isEmpty);
    });

    testWidgets("shows a label the catalogue doesn't list, so it can go",
        (tester) async {
      // Deleted from the catalogue, or the catalogue failed to load: either
      // way the thread still carries it.
      const gone = ThreadLabel(id: 9, name: 'Retired', color: '#808080');
      final saves = await _open(
        tester,
        thread: _thread(labels: [gone]),
        catalogue: const [],
      );

      expect(find.text('Retired'), findsOneWidget);
      await tester.tap(find.text('Retired'));
      await tester.pump();
      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(saves.labelIds.single, isEmpty);
    });

    testWidgets('a failed save stays open and says why', (tester) async {
      final saves = await _open(tester, thread: _thread());
      saves.answer = () => 'Could not save the thread. Please try again.';

      await tester.tap(_save);
      await tester.pumpAndSettle();

      expect(find.text('Thread properties'), findsOneWidget);
      expect(
        find.text('Could not save the thread. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
