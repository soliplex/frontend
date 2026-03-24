import 'package:go_router/go_router.dart';

import '../core/shell_config.dart';
import 'auth/server_manager.dart';
import 'lobby/ui/room_placeholder_screen.dart';

ModuleContribution roomPlaceholder({
  required ServerManager serverManager,
}) {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId',
        pageBuilder: (_, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias);
          return NoTransitionPage(
            child: RoomPlaceholderScreen(
              serverAlias: alias,
              serverId: entry?.serverId,
              roomId: state.pathParameters['roomId']!,
            ),
          );
        },
      ),
    ],
  );
}
