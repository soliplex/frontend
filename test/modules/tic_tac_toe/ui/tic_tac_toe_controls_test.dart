import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/board_render_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_server_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/ui/tic_tac_toe_controls.dart';

BoardRenderState renderWith({
  bool canSend = false,
  bool canCancel = false,
  bool canUndo = false,
  bool canRedo = false,
}) {
  return BoardRenderState(
    cells: List.generate(
      3,
      (_) => List.generate(
        3,
        (_) => const CellRender(
          mark: null,
          isPending: false,
          isWinning: false,
        ),
      ),
    ),
    turn: TicTacToePlayer.user,
    winner: null,
    winningLine: null,
    pending: null,
    canSend: canSend,
    canCancel: canCancel,
    canUndo: canUndo,
    canRedo: canRedo,
    canNewGame: true,
    inFlight: canCancel,
  );
}

void main() {
  testWidgets('Send disabled when canSend=false', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeControls(
            render: renderWith(),
            autoSend: false,
            lastError: null,
            onSend: () {},
            onCancel: () {},
            onUndo: () {},
            onRedo: () {},
            onToggleAutoSend: () {},
            onToggleFullscreen: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    final sendBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Send'),
    );
    expect(sendBtn.onPressed, isNull);
  });

  testWidgets('Send enabled and triggers callback when canSend=true',
      (tester) async {
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeControls(
            render: renderWith(canSend: true),
            autoSend: false,
            lastError: null,
            onSend: () => sends++,
            onCancel: () {},
            onUndo: () {},
            onRedo: () {},
            onToggleAutoSend: () {},
            onToggleFullscreen: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    expect(sends, 1);
  });

  testWidgets('Undo / Redo enablement reflects render flags', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeControls(
            render: renderWith(canUndo: true),
            autoSend: false,
            lastError: null,
            onSend: () {},
            onCancel: () {},
            onUndo: () {},
            onRedo: () {},
            onToggleAutoSend: () {},
            onToggleFullscreen: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    final undoBtn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Undo'),
        matching: find.byType(IconButton),
      ),
    );
    expect(undoBtn.onPressed, isNotNull);
    final redoBtn = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Redo'),
        matching: find.byType(IconButton),
      ),
    );
    expect(redoBtn.onPressed, isNull);
  });

  testWidgets('renders error chip when lastError is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeControls(
            render: renderWith(),
            autoSend: false,
            lastError: TicTacToeError.network,
            onSend: () {},
            onCancel: () {},
            onUndo: () {},
            onRedo: () {},
            onToggleAutoSend: () {},
            onToggleFullscreen: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('tictactoe-error-chip')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Retry callback fires', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicTacToeControls(
            render: renderWith(),
            autoSend: false,
            lastError: TicTacToeError.network,
            onSend: () {},
            onCancel: () {},
            onUndo: () {},
            onRedo: () {},
            onToggleAutoSend: () {},
            onToggleFullscreen: () {},
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
}
