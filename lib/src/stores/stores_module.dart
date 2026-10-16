import '../core/app_module.dart';
import '../modules/auth/server_manager.dart';
import 'database_selections.dart';
import 'document_selections.dart';
import 'lobby_read_markers.dart' show RoomReadMarkers, ServerReadMarkers;
import 'removed_server_cleanup.dart';
import 'run_registry.dart';

/// Owns the state more than one feature reads (ADR-005), and the
/// [RemovedServerCleanup] that clears it when a server is removed.
///
/// Route-less: it contributes no routes, overrides or redirect. The kit
/// registers it before the feature modules and hands them its stores, so it
/// is disposed after them. A store that must be cleared on server removal is
/// added here and to [RemovedServerCleanup], in one place.
class StoresAppModule extends AppModule {
  StoresAppModule({required ServerManager serverManager})
      : registry = RunRegistry(servers: serverManager.servers),
        roomReadMarkers = RoomReadMarkers(),
        serverReadMarkers = ServerReadMarkers(),
        documentSelections = DocumentSelections(),
        databaseSelections = DatabaseSelections() {
    _removedServerCleanup = RemovedServerCleanup(
      serverManager: serverManager,
      roomReadMarkers: roomReadMarkers,
      serverReadMarkers: serverReadMarkers,
      documentSelections: documentSelections,
      databaseSelections: databaseSelections,
    );
  }

  /// The runs in flight across every room, read by the lobby and the room.
  final RunRegistry registry;

  /// Room read markers, so a room stamped read in the room screen clears its
  /// lobby unread dot immediately, with no storage race.
  final RoomReadMarkers roomReadMarkers;

  /// Server read markers. A server marker floors every room and thread on the
  /// server, in the lobby and in the room's rail alike.
  final ServerReadMarkers serverReadMarkers;

  /// The room's per-thread document filter.
  final DocumentSelections documentSelections;

  /// The room's per-thread database selections.
  final DatabaseSelections databaseSelections;

  late final RemovedServerCleanup _removedServerCleanup;

  @override
  String get namespace => 'stores';

  @override
  ModuleRoutes build() => const ModuleRoutes();

  @override
  Future<void> onDispose() async {
    _removedServerCleanup.dispose();
    registry.dispose();
  }
}
