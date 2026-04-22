import 'package:go_router/go_router.dart';

import '../../core/shell_config.dart';
import '../auth/require_connected_server.dart';
import '../auth/server_manager.dart';
import 'agent_runtime_manager.dart';
import 'document_selections.dart';
import 'message_expansions.dart';
import 'room_providers.dart';
import 'run_registry.dart';
import 'ui/room_info_screen.dart';
import 'ui/room_screen.dart';
import 'upload_tracker_registry.dart';

ModuleContribution roomModule({
  required ServerManager serverManager,
  required AgentRuntimeManager runtimeManager,
  required RunRegistry registry,
  bool enableDocumentFilter = false,
}) {
  final documentSelections = DocumentSelections();
  final uploadRegistry = UploadTrackerRegistry(servers: serverManager.servers);
  final messageExpansions = MessageExpansions();
  return ModuleContribution(
    overrides: [
      messageExpansionsProvider.overrideWithValue(messageExpansions),
    ],
    routes: [
      GoRoute(
        path: '/room/:serverAlias/:roomId/info',
        redirect: (context, state) => requireConnectedServer(
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
              uploadRegistry: uploadRegistry,
            ),
          );
        },
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId',
        serverManager,
        runtimeManager,
        registry,
        uploadRegistry,
        enableDocumentFilter,
        documentSelections,
      ),
      _buildRoute(
        '/room/:serverAlias/:roomId/thread/:threadId',
        serverManager,
        runtimeManager,
        registry,
        uploadRegistry,
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
  UploadTrackerRegistry uploadRegistry,
  bool enableDocumentFilter,
  DocumentSelections documentSelections,
) {
  return GoRoute(
    path: path,
    redirect: (context, state) => requireConnectedServer(
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
          uploadRegistry: uploadRegistry,
          enableDocumentFilter: enableDocumentFilter,
          documentSelections: documentSelections,
        ),
      );
    },
  );
}
