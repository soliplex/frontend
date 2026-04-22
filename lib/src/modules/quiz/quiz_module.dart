import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'ui/quiz_screen.dart';

class QuizAppModule extends AppModule {
  QuizAppModule({required this.serverManager});

  final ServerManager serverManager;

  @override
  String get namespace => 'quiz';

  @override
  ModuleRoutes build(AppModuleContext ctx) => ModuleRoutes(
        routes: [
          GoRoute(
            path: '/room/:serverAlias/:roomId/quiz/:quizId',
            redirect: (context, state) => requireConnectedServer(
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
