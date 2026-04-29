/// Wire keys for the `_inbox.tic_tac_toe` payload.
class TicTacToeIntent {
  const TicTacToeIntent._();

  static const surfaceKey = 'tic_tac_toe';
  static const intentKey = 'intent';

  // Intent values
  static const newGame = 'new_game';
  static const play = 'play';
  static const undo = 'undo';
  static const redo = 'redo';
}
