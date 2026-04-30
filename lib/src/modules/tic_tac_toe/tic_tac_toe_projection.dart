import 'package:soliplex_client/soliplex_client.dart' show StateProjection;

import 'tic_tac_toe_server_state.dart';
import 'tic_tac_toe_state.dart';

class TicTacToeProjection extends StateProjection<TicTacToeServerState?> {
  const TicTacToeProjection();

  @override
  TicTacToeServerState? project(Map<String, dynamic> agentState) {
    final game = agentState['game'];
    if (game is! Map<String, dynamic>) return null;
    try {
      return TicTacToeServerState(
        id: game['id'] as String,
        board: _board(game['board']),
        moves: _moves(game['moves']),
        turn: _player(game['turn'] as String),
        winner: _outcome(game['winner']),
        winningLine: _winningLine(game['winning_line']),
      );
    } on Object {
      // Tolerant per the StateProjection contract: malformed input
      // produces null rather than throwing.
      return null;
    }
  }

  static List<List<String?>> _board(Object? raw) {
    if (raw is! List) throw const FormatException('board not a list');
    return raw
        .cast<List>()
        .map((row) => row.map((c) => c as String?).toList(growable: false))
        .toList(growable: false);
  }

  static List<Move> _moves(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .cast<Map<String, dynamic>>()
        .map(
          (m) => Move(
            player: _player(m['player'] as String),
            row: (m['row'] as num).toInt(),
            col: (m['col'] as num).toInt(),
            mark: m['mark'] as String,
          ),
        )
        .toList(growable: false);
  }

  static TicTacToePlayer _player(String s) => switch (s) {
        'user' => TicTacToePlayer.user,
        'agent' => TicTacToePlayer.agent,
        _ => throw FormatException('unknown player $s'),
      };

  static TicTacToeOutcome? _outcome(Object? raw) {
    if (raw == null) return null;
    return switch (raw as String) {
      'user' => TicTacToeOutcome.user,
      'agent' => TicTacToeOutcome.agent,
      'draw' => TicTacToeOutcome.draw,
      _ => throw FormatException('unknown outcome $raw'),
    };
  }

  static List<Cell>? _winningLine(Object? raw) {
    if (raw == null) return null;
    return (raw as List)
        .cast<Map<String, dynamic>>()
        .map((c) => Cell((c['row'] as num).toInt(), (c['col'] as num).toInt()))
        .toList(growable: false);
  }
}
