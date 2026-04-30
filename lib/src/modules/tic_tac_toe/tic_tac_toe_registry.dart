import 'package:soliplex_agent/soliplex_agent.dart';

import 'tic_tac_toe_controller.dart';

class TicTacToeRegistry {
  final Map<ThreadKey, TicTacToeController> _controllers = {};
  bool _disposed = false;

  TicTacToeController controllerFor(
    ThreadKey key,
    TicTacToeController Function() factory,
  ) {
    assert(!_disposed, 'controllerFor on disposed TicTacToeRegistry');
    return _controllers.putIfAbsent(key, factory);
  }

  void disposeFor(ThreadKey key) {
    _controllers.remove(key)?.dispose();
  }

  void disposeAll() {
    if (_disposed) return;
    _disposed = true;
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }
}
