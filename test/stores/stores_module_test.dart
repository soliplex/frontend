import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_client/soliplex_client.dart' show RagDocument;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/stores/stores_module.dart';

import '../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    )..addServer(
        serverId: 's1',
        serverUrl: Uri.parse('http://s1.test'),
        requiresAuth: false,
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const doc = RagDocument(id: 'd1', title: 'Doc');

  test('contributes no routes, overrides or redirect', () async {
    final stores = StoresAppModule(serverManager: _createManager());
    addTearDown(stores.onDispose);

    final routes = stores.build();

    expect(stores.namespace, 'stores');
    expect(routes.routes, isEmpty);
    expect(routes.overrides, isEmpty);
    expect(routes.redirect, isNull);
    expect(routes.publicPaths, isEmpty);
  });

  test('clears its stores when a server is removed', () async {
    final manager = _createManager();
    final stores = StoresAppModule(serverManager: manager);
    addTearDown(stores.onDispose);
    stores.documentSelections
        .set(serverId: 's1', roomId: 'r', threadId: 't', docs: {doc});

    manager.removeServer('s1');
    await pumpEventQueue();

    expect(
      stores.documentSelections.get(serverId: 's1', roomId: 'r', threadId: 't'),
      isEmpty,
    );
  });

  test('stops clearing once disposed', () async {
    final manager = _createManager();
    final stores = StoresAppModule(serverManager: manager);
    stores.documentSelections
        .set(serverId: 's1', roomId: 'r', threadId: 't', docs: {doc});

    await stores.onDispose();
    manager.removeServer('s1');
    await pumpEventQueue();

    expect(
      stores.documentSelections.get(serverId: 's1', roomId: 'r', threadId: 't'),
      {doc},
    );
  });
}
