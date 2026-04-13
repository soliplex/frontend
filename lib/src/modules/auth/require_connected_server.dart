import 'server_manager.dart';

/// Returns '/lobby' if [alias] does not resolve to a connected server,
/// otherwise returns null (allowing navigation to proceed).
String? requireConnectedServer(ServerManager serverManager, String? alias) {
  if (alias == null) return '/lobby';
  final entry = serverManager.entryByAlias(alias);
  if (entry == null || !entry.isConnected) return '/lobby';
  return null;
}
