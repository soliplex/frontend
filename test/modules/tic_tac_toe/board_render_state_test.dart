import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/board_render_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_server_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_state.dart';

void main() {
  TicTacToeServerState emptyServer({
    TicTacToeOutcome? winner,
    List<Cell>? winningLine,
    TicTacToePlayer turn = TicTacToePlayer.user,
  }) =>
      TicTacToeServerState(
        id: 'g1',
        board: List.generate(3, (_) => List.filled(3, null)),
        moves: const [],
        turn: turn,
        winner: winner,
        winningLine: winningLine,
      );

  test('returns null when server state is null', () {
    final r = BoardRenderState.compose(
      server: null,
      client: const TicTacToeClientState(),
    );
    expect(r, isNull);
  });

  test('compositing applies pending overlay', () {
    final r = BoardRenderState.compose(
      server: emptyServer(),
      client: const TicTacToeClientState(pending: Cell(1, 1)),
    )!;
    expect(r.cells[1][1].mark, 'X');
    expect(r.cells[1][1].isPending, isTrue);
  });

  test('canSend false when winner != null', () {
    final r = BoardRenderState.compose(
      server: emptyServer(winner: TicTacToeOutcome.user),
      client: const TicTacToeClientState(pending: Cell(1, 1)),
    )!;
    expect(r.canSend, isFalse);
  });

  test('canCancel iff inFlight', () {
    final ready = BoardRenderState.compose(
      server: emptyServer(),
      client: const TicTacToeClientState(),
    )!;
    expect(ready.canCancel, isFalse);
    final inflight = BoardRenderState.compose(
      server: emptyServer(),
      client: const TicTacToeClientState(inFlight: true),
    )!;
    expect(inflight.canCancel, isTrue);
  });

  test('winning cells flagged', () {
    final r = BoardRenderState.compose(
      server: emptyServer(
        winner: TicTacToeOutcome.user,
        winningLine: const [Cell(0, 0), Cell(1, 1), Cell(2, 2)],
      ),
      client: const TicTacToeClientState(),
    )!;
    expect(r.cells[0][0].isWinning, isTrue);
    expect(r.cells[1][1].isWinning, isTrue);
    expect(r.cells[0][1].isWinning, isFalse);
  });
}
