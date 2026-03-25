import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/server_manager.dart';
import 'ui/room_screen.dart';

ModuleContribution roomModule({
  required ServerManager serverManager,
}) {
  return ModuleContribution(
    routes: [
      _buildRoute('/room/:serverAlias/:roomId', serverManager),
      _buildRoute('/room/:serverAlias/:roomId/:threadId', serverManager),
    ],
  );
}

GoRoute _buildRoute(String path, ServerManager serverManager) {
  return GoRoute(
    path: path,
    redirect: (context, state) {
      final alias = state.pathParameters['serverAlias']!;
      final entry = serverManager.entryByAlias(alias);
      if (entry == null || !entry.isConnected) return '/lobby';
      return null;
    },
    pageBuilder: (context, state) {
      final alias = state.pathParameters['serverAlias']!;
      final entry = serverManager.entryByAlias(alias)!;
      return NoTransitionPage(
        child: RoomScreen(
          serverEntry: entry,
          roomId: state.pathParameters['roomId']!,
          threadId: state.pathParameters['threadId'],
        ),
      );
    },
  );
}
