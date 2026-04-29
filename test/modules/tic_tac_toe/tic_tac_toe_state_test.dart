import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_state.dart';

void main() {
  group('Cell', () {
    test('value equality', () {
      expect(const Cell(1, 2), const Cell(1, 2));
      expect(const Cell(1, 2), isNot(const Cell(2, 1)));
    });
  });

  group('TurnPair', () {
    test('agent move is optional', () {
      const tp = TurnPair(user: Cell(0, 0));
      expect(tp.agent, isNull);
    });
  });

  group('TicTacToeClientState', () {
    test('default values', () {
      const s = TicTacToeClientState();
      expect(s.pending, isNull);
      expect(s.redoStack, isEmpty);
      expect(s.viewMode, TicTacToeViewMode.hidden);
      expect(s.autoSend, isFalse);
      expect(s.inFlight, isFalse);
      expect(s.lastError, isNull);
      expect(s.unreadChatWhileFullscreen, 0);
    });

    test('copyWith pending', () {
      const s = TicTacToeClientState();
      final s2 = s.copyWith(pending: const Cell(1, 1));
      expect(s2.pending, const Cell(1, 1));
      expect(s.pending, isNull); // original unchanged
    });

    test('copyWith clearPending forces null', () {
      const s = TicTacToeClientState(pending: Cell(0, 0));
      final s2 = s.copyWith(clearPending: true);
      expect(s2.pending, isNull);
    });
  });
}
