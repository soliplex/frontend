import 'package:flutter/foundation.dart' show immutable;

import 'tic_tac_toe_server_state.dart';
import 'tic_tac_toe_state.dart';

@immutable
class CellRender {
  const CellRender({
    required this.mark,
    required this.serverMark,
    required this.isPending,
    required this.isWinning,
  });

  /// What to display: server mark, OR the pending overlay's mark if
  /// the cell is staged but not yet committed, OR null when empty.
  final String? mark;

  /// What the server actually has at this cell, ignoring any pending
  /// overlay. Used by the widget's enable rule so a pending cell stays
  /// tappable (re-tap toggles the pending off, per the spec).
  final String? serverMark;

  final bool isPending;
  final bool isWinning;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellRender &&
          mark == other.mark &&
          serverMark == other.serverMark &&
          isPending == other.isPending &&
          isWinning == other.isWinning;

  @override
  int get hashCode => Object.hash(mark, serverMark, isPending, isWinning);
}

@immutable
class BoardRenderState {
  const BoardRenderState({
    required this.cells,
    required this.turn,
    required this.winner,
    required this.winningLine,
    required this.pending,
    required this.canSend,
    required this.canCancel,
    required this.canUndo,
    required this.canRedo,
    required this.canNewGame,
    required this.inFlight,
  });

  final List<List<CellRender>> cells;
  final TicTacToePlayer turn;
  final TicTacToeOutcome? winner;
  final List<Cell>? winningLine;
  final Cell? pending;
  final bool canSend;
  final bool canCancel;
  final bool canUndo;
  final bool canRedo;
  final bool canNewGame;
  final bool inFlight;

  static const _userMark = 'X';

  static BoardRenderState? compose({
    required TicTacToeServerState? server,
    required TicTacToeClientState client,
  }) {
    if (server == null) return null;
    final winning = <Cell>{...?server.winningLine};
    final cells = List.generate(3, (r) {
      return List.generate(3, (c) {
        final serverMark = server.board[r][c];
        final isPending = client.pending == Cell(r, c) && serverMark == null;
        return CellRender(
          mark: serverMark ?? (isPending ? _userMark : null),
          serverMark: serverMark,
          isPending: isPending,
          isWinning: winning.contains(Cell(r, c)),
        );
      });
    });
    final movesEmpty = server.moves.isEmpty;
    return BoardRenderState(
      cells: cells,
      turn: server.turn,
      winner: server.winner,
      winningLine: server.winningLine,
      pending: client.pending,
      canSend: !client.inFlight &&
          client.pending != null &&
          server.winner == null &&
          server.turn == TicTacToePlayer.user,
      canCancel: client.inFlight,
      canUndo: !client.inFlight && (client.pending != null || !movesEmpty),
      canRedo: !client.inFlight &&
          client.pending == null &&
          client.redoStack.isNotEmpty,
      canNewGame: !client.inFlight,
      inFlight: client.inFlight,
    );
  }
}
