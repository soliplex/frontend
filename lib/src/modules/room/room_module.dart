import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/server_manager.dart';
import 'ui/room_screen.dart';

ModuleContribution roomModule({
  required ServerManager serverManager,
}) {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId',
        pageBuilder: (context, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias);
          if (entry == null || !entry.isConnected) {
            return const NoTransitionPage(
              child: _RedirectToLobby(),
            );
          }
          return NoTransitionPage(
            child: RoomScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              threadId: null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/room/:serverAlias/:roomId/:threadId',
        pageBuilder: (context, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias);
          if (entry == null || !entry.isConnected) {
            return const NoTransitionPage(
              child: _RedirectToLobby(),
            );
          }
          return NoTransitionPage(
            child: RoomScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              threadId: state.pathParameters['threadId'],
            ),
          );
        },
      ),
    ],
  );
}

class _RedirectToLobby extends StatelessWidget {
  const _RedirectToLobby();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/lobby');
    });
    return const SizedBox.shrink();
  }
}
