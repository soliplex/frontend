import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import '../auth/server_manager.dart';
import 'ui/lobby_screen.dart';

class LobbyAppModule extends AppModule {
  LobbyAppModule({required this.serverManager});

  final ServerManager serverManager;

  @override
  String get namespace => 'lobby';

  @override
  ModuleRoutes build() => .new(
    routes: [
      GoRoute(
        path: AppRoutes.lobby,
        pageBuilder: (_, _) =>
            NoTransitionPage(child: LobbyScreen(serverManager: serverManager)),
      ),
    ],
  );
}
