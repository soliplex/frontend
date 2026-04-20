import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'ui/quiz_screen.dart';

ModuleContribution quizModule({required ServerManager serverManager}) {
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId/quiz/:quizId',
        redirect:
            (context, state) => requireConnectedServer(
              serverManager,
              state.pathParameters['serverAlias'],
            ),
        pageBuilder: (context, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias);
          if (entry == null || !entry.isConnected) {
            return const NoTransitionPage(child: SizedBox.shrink());
          }
          return NoTransitionPage(
            child: QuizScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              quizId: state.pathParameters['quizId']!,
              returnRoute: state.uri.queryParameters['from'],
            ),
          );
        },
      ),
    ],
  );
}
