import 'package:flutter/foundation.dart' show immutable, listEquals;

import 'tic_tac_toe_state.dart';

enum TicTacToePlayer { user, agent }

enum TicTacToeOutcome { user, agent, draw }

@immutable
class Move {
  const Move({
    required this.player,
    required this.row,
    required this.col,
    required this.mark,
  });

  final TicTacToePlayer player;
  final int row;
  final int col;
  final String mark; // "X" or "O"

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Move &&
          player == other.player &&
          row == other.row &&
          col == other.col &&
          mark == other.mark;

  @override
  int get hashCode => Object.hash(player, row, col, mark);
}

@immutable
class TicTacToeServerState {
  const TicTacToeServerState({
    required this.id,
    required this.board,
    required this.moves,
    required this.turn,
    required this.winner,
    required this.winningLine,
  });

  final String id;
  final List<List<String?>> board;
  final List<Move> moves;
  final TicTacToePlayer turn;
  final TicTacToeOutcome? winner;
  final List<Cell>? winningLine;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TicTacToeServerState &&
          id == other.id &&
          _boardEquals(board, other.board) &&
          listEquals(moves, other.moves) &&
          turn == other.turn &&
          winner == other.winner &&
          listEquals(winningLine, other.winningLine);

  @override
  int get hashCode => Object.hash(
        id,
        _boardHash(board),
        Object.hashAll(moves),
        turn,
        winner,
        winningLine == null ? null : Object.hashAll(winningLine!),
      );

  static bool _boardEquals(List<List<String?>> a, List<List<String?>> b) {
    if (a.length != b.length) return false;
    for (var r = 0; r < a.length; r++) {
      if (!listEquals(a[r], b[r])) return false;
    }
    return true;
  }

  static int _boardHash(List<List<String?>> b) =>
      Object.hashAll(b.map(Object.hashAll));
}
