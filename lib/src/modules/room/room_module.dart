import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
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

class RoomAppModule extends AppModule {
  RoomAppModule({
    required this.serverManager,
    required this.runtimeManager,
    required this.registry,
    this.enableDocumentFilter = false,
  })  : _documentSelections = DocumentSelections(),
        _messageExpansions = MessageExpansions(),
        _uploadRegistry = UploadTrackerRegistry(servers: serverManager.servers);

  final ServerManager serverManager;
  final AgentRuntimeManager runtimeManager;
  final RunRegistry registry;
  final bool enableDocumentFilter;

  final DocumentSelections _documentSelections;
  final MessageExpansions _messageExpansions;
  final UploadTrackerRegistry _uploadRegistry;

  @override
  String get namespace => 'room';

  @override
  ModuleRoutes build() => ModuleRoutes(
        overrides: [
          messageExpansionsProvider.overrideWithValue(_messageExpansions),
          runRegistryProvider.overrideWithValue(registry),
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
                  uploadRegistry: _uploadRegistry,
                ),
              );
            },
          ),
          _buildRoute('/room/:serverAlias/:roomId'),
          _buildRoute('/room/:serverAlias/:roomId/thread/:threadId'),
        ],
      );

  GoRoute _buildRoute(String path) {
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
            uploadRegistry: _uploadRegistry,
            enableDocumentFilter: enableDocumentFilter,
            documentSelections: _documentSelections,
          ),
        );
      },
    );
  }

  @override
  Future<void> onDispose() async {
    await runtimeManager.dispose();
    registry.dispose();
    _uploadRegistry.dispose();
  }
}
