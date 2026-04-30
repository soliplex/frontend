import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_controller.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_registry.dart';

import 'fakes.dart';

void main() {
  test('controllerFor caches by ThreadKey', () {
    final reg = TicTacToeRegistry();
    final runtime = FakeAgentRuntime();
    final c1 = reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't'),
      () => TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: runtime,
      ),
    );
    final c2 = reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't'),
      () => fail('factory should not be invoked twice'),
    );
    expect(identical(c1, c2), isTrue);
  });

  test('disposeFor removes and disposes', () {
    final reg = TicTacToeRegistry();
    final runtime = FakeAgentRuntime();
    reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't'),
      () => TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: runtime,
      ),
    );
    reg.disposeFor((serverId: 's', roomId: 'r', threadId: 't'));
    var factoryCalls = 0;
    reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't'),
      () {
        factoryCalls++;
        return TicTacToeController(
          threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
          runtime: runtime,
        );
      },
    );
    expect(factoryCalls, 1);
  });

  test('disposeAll clears all', () {
    final reg = TicTacToeRegistry();
    final runtime = FakeAgentRuntime();
    reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't1'),
      () => TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't1'),
        runtime: runtime,
      ),
    );
    reg.controllerFor(
      (serverId: 's', roomId: 'r', threadId: 't2'),
      () => TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't2'),
        runtime: runtime,
      ),
    );
    reg.disposeAll();
    // Cannot call controllerFor after disposeAll (assert).
  });
}
