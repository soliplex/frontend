import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/board_render_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/ui/tic_tac_toe_cell.dart';

void main() {
  testWidgets('renders mark text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeCell(
            render: const CellRender(
              mark: 'X',
              serverMark: 'X',
              isPending: false,
              isWinning: false,
            ),
            enabled: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets('renders pending mark with the outline color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeCell(
            render: const CellRender(
              mark: 'X',
              serverMark: null,
              isPending: true,
              isWinning: false,
            ),
            enabled: true,
            onTap: () {},
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('X'));
    final BuildContext context = tester.element(find.byType(TicTacToeCell));
    expect(text.style?.color, Theme.of(context).colorScheme.outline);
  });

  testWidgets('disabled when enabled false', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeCell(
            render: const CellRender(
              mark: null,
              serverMark: null,
              isPending: false,
              isWinning: false,
            ),
            enabled: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TicTacToeCell));
    expect(taps, 0);
  });
}
