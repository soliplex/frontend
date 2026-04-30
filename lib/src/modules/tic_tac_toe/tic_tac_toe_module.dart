import '../../core/app_module.dart';
import '../room/room_providers.dart';
import 'tic_tac_toe_providers.dart';
import 'tic_tac_toe_registry.dart';
import 'ui/tic_tac_toe_board.dart';
import 'ui/tic_tac_toe_toolbar_button.dart';

class TicTacToeAppModule extends AppModule {
  TicTacToeAppModule();

  TicTacToeRegistry? _registry;

  @override
  String get namespace => 'tic_tac_toe';

  @override
  ModuleRoutes build() {
    final registry = TicTacToeRegistry();
    _registry = registry;
    return ModuleRoutes(
      overrides: [
        tictactoeRegistryProvider.overrideWithValue(registry),
        roomAboveChatInputBuildersProvider.overrideWithValue(
          [(_) => const TicTacToeBoard()],
        ),
        roomChatInputToolbarBuildersProvider.overrideWithValue(
          [(_) => const TicTacToeToolbarButton()],
        ),
      ],
    );
  }

  @override
  Future<void> onDispose() async {
    _registry?.disposeAll();
  }
}
