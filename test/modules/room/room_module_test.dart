import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  test('contributes room routes', () {
    final manager = _createManager();
    final contribution = roomModule(serverManager: manager);
    final paths =
        contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
    expect(paths, contains('/room/:serverAlias/:roomId'));
    expect(paths, contains('/room/:serverAlias/:roomId/:threadId'));
  });

  test('contributes no overrides in Slice A', () {
    final manager = _createManager();
    final contribution = roomModule(serverManager: manager);
    expect(contribution.overrides, isEmpty);
  });
}
