import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'agent_runtime_manager.dart';
import 'document_selections.dart';
import 'run_registry.dart';
import 'ui/room_info_screen.dart';
import 'ui/room_screen.dart';

ModuleContribution roomModule({
  required ServerManager serverManager,
  required AgentRuntimeManager runtimeManager,
  required RunRegistry registry,
  bool enableDocumentFilter = false,
}) {
  final documentSelections = DocumentSelections();
  return ModuleContribution(
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId/info',
        redirect:
            (context, state) => requireConnectedServer(
              serverManager,
              state.pathParameters['serverAlias'],
            ),
        pageBuilder: (context, state) {
          final alias = state.pathParameters['serverAlias']!;
          final entry = serverManager.entryByAlias(alias)!;
          return NoTransitionPage(
            child: RoomInfoScreen(
              serverEntry: entry,
              roomId: state.pathParameters['roomId']!,
              toolRegistryResolver: runtimeManager.toolRegistryResolver,
            ),
          );
        },
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId',
        serverManager,
        runtimeManager,
        registry,
        enableDocumentFilter,
        documentSelections,
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId/thread/:threadId',
        serverManager,
        runtimeManager,
        registry,
        enableDocumentFilter,
        documentSelections,
      ),
    ],
  );
}

GoRoute _buildRoute(
  String path,
  ServerManager serverManager,
  AgentRuntimeManager runtimeManager,
  RunRegistry registry,
  bool enableDocumentFilter,
  DocumentSelections documentSelections,
) {
  return GoRoute(
    path: path,
    redirect:
        (context, state) => requireConnectedServer(
          serverManager,
          state.pathParameters['serverAlias'],
        ),
    pageBuilder: (context, state) {
      final alias = state.pathParameters['serverAlias']!;
      final entry = serverManager.entryByAlias(alias)!;
      return NoTransitionPage(
        child: RoomScreen(
          serverEntry: entry,
          roomId: state.pathParameters['roomId']!,
          threadId: state.pathParameters['threadId'],
          runtimeManager: runtimeManager,
          registry: registry,
          enableDocumentFilter: enableDocumentFilter,
          documentSelections: documentSelections,
        ),
      );
    },
  );
}
