import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_projection.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_server_state.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_state.dart';

void main() {
  const projection = TicTacToeProjection();

  test('returns null when game key is missing', () {
    expect(projection.project(const {}), isNull);
  });

  test('returns null when game is malformed', () {
    expect(projection.project(const {'game': 'bogus'}), isNull);
  });

  test('parses a valid game state', () {
    final result = projection.project({
      'game': {
        'id': 'g1',
        'board': [
          ['X', null, null],
          [null, 'O', null],
          [null, null, null],
        ],
        'moves': [
          {'player': 'user', 'row': 0, 'col': 0, 'mark': 'X'},
          {'player': 'agent', 'row': 1, 'col': 1, 'mark': 'O'},
        ],
        'turn': 'user',
        'winner': null,
        'winning_line': null,
      },
    });
    expect(result, isNotNull);
    expect(result!.id, 'g1');
    expect(result.turn, TicTacToePlayer.user);
    expect(result.winner, isNull);
    expect(result.moves, hasLength(2));
  });

  test('parses winning_line into List<Cell>', () {
    final result = projection.project({
      'game': {
        'id': 'g1',
        'board': [
          ['X', 'X', 'X'],
          [null, null, null],
          [null, null, null],
        ],
        'moves': [],
        'turn': 'user',
        'winner': 'user',
        'winning_line': [
          {'row': 0, 'col': 0},
          {'row': 0, 'col': 1},
          {'row': 0, 'col': 2},
        ],
      },
    });
    expect(result?.winner, TicTacToeOutcome.user);
    expect(result?.winningLine, [
      const Cell(0, 0),
      const Cell(0, 1),
      const Cell(0, 2),
    ]);
  });

  test('rebuild radius — equal projection inputs yield equal outputs', () {
    // Projection MUST produce value-equal outputs so computed signals
    // can short-circuit when an unrelated agentState change leaves
    // the game slice untouched.
    final input1 = {
      'game': {
        'id': 'g1',
        'board': [
          [null, null, null],
          [null, null, null],
          [null, null, null],
        ],
        'moves': <dynamic>[],
        'turn': 'user',
        'winner': null,
        'winning_line': null,
      },
      'unrelated': 'value-A',
    };
    final input2 = {
      ...input1,
      'unrelated': 'value-B', // changed; game slice unchanged
    };
    final out1 = projection.project(input1);
    final out2 = projection.project(input2);
    expect(out1, equals(out2));
    expect(out1.hashCode, out2.hashCode);
  });
}
