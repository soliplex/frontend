import '../../core/routes.dart';
import 'server_manager.dart';

/// Returns the lobby path if [alias] does not resolve to a connected server,
/// otherwise returns null (allowing navigation to proceed).
String? requireConnectedServer(ServerManager serverManager, String? alias) {
  if (alias == null) return AppRoutes.lobby;
  final entry = serverManager.entryByAlias(alias);
  if (entry == null || !entry.isConnected) return AppRoutes.lobby;
  return null;
}
