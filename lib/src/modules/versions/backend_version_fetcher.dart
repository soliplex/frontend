import 'package:soliplex_client/soliplex_client.dart';

import '../auth/server_entry.dart';

typedef BackendVersionFetcher = Future<BackendVersionInfo> Function(
  ServerEntry entry,
);

Future<BackendVersionInfo> fetchBackendVersionInfo(ServerEntry entry) =>
    entry.connection.api.getBackendVersionInfo();
