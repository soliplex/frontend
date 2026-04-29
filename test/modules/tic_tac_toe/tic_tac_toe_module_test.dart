import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_module.dart';

void main() {
  test('build returns overrides for registry + two slots', () {
    final mod = TicTacToeAppModule();
    final routes = mod.build();
    expect(routes.routes, isEmpty);
    expect(routes.overrides, hasLength(3));
  });

  test('onDispose disposes the registry', () async {
    final mod = TicTacToeAppModule();
    mod.build();
    await mod.onDispose();
  });
}
