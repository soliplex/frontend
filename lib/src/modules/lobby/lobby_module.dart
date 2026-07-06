import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/app_identity.dart';
import '../../core/routes.dart';
import '../auth/server_manager.dart';
import '../room/run_registry.dart';
import 'lobby_read_markers.dart' show RoomReadMarkers, ServerReadMarkers;
import 'ui/lobby_screen.dart';

class LobbyAppModule extends AppModule {
  LobbyAppModule({
    required this.serverManager,
    required this.identity,
    required this.registry,
    required this.roomReadMarkers,
    required this.serverReadMarkers,
  });

  final ServerManager serverManager;

  /// Brand identity surfaced in the sidebar header (logo + app name).
  final AppIdentity identity;

  /// Shared run registry; the lobby watches it to refresh a room's unread dot
  /// when a background run finishes while the user sits in the lobby.
  final RunRegistry registry;

  /// Shared room read markers, also stamped by the room screen so a room read
  /// there clears its lobby unread dot immediately.
  final RoomReadMarkers roomReadMarkers;

  /// Shared server read markers, also watched by the room screen. A server
  /// marker floors every room's unread dot on the server.
  final ServerReadMarkers serverReadMarkers;

  @override
  String get namespace => 'lobby';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(
            path: AppRoutes.lobby,
            pageBuilder: (_, __) => NoTransitionPage(
              child: LobbyScreen(
                serverManager: serverManager,
                identity: identity,
                registry: registry,
                roomReadMarkers: roomReadMarkers,
                serverReadMarkers: serverReadMarkers,
              ),
            ),
          ),
        ],
      );
}
