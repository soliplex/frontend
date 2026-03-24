import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/server_manager.dart';
import 'ui/lobby_screen.dart';

ModuleContribution lobbyModule({
  required ServerManager serverManager,
}) {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/lobby',
        pageBuilder: (_, __) => NoTransitionPage(
          child: LobbyScreen(serverManager: serverManager),
        ),
      ),
    ],
  );
}
