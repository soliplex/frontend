import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';

import 'platform_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installPlatformMocks();

  test('buildStandardKit returns the coherent standard set', () async {
    final kit = await buildStandardKit(identity: AppIdentity.soliplex);

    final namespaces = kit.modules.map((m) => m.namespace).toList();
    expect(
      namespaces,
      ['diagnostics', 'auth', 'lobby', 'room', 'quiz', 'versions'],
      reason: 'the standard composition, in registration order',
    );
    expect(kit.initialRoute, AppRoutes.home);
  });

  test('initialRoute is the auth callback when callback params are present',
      () async {
    final kit = await buildStandardKit(
      identity: AppIdentity.soliplex,
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
    );

    expect(kit.initialRoute, AppRoutes.authCallback);
  });

  test('initialRoute is the lobby when a restored server authenticates',
      () async {
    // A returning user with a stored no-auth server floors the session to
    // Authenticated, so boot lands on the lobby, not the home/login screen.
    // The has-launched flag keeps the fresh-install sweep from clearing it.
    SharedPreferences.setMockInitialValues({'soliplex_has_launched': true});
    seedSecureStorage({
      'soliplex_server_local': jsonEncode(
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        ).toJson(),
      ),
    });

    final kit = await buildStandardKit(identity: AppIdentity.soliplex);

    expect(kit.initialRoute, AppRoutes.lobby);
  });

  test('enableDocumentFilter is forwarded to the room module', () async {
    final off = await buildStandardKit(
      identity: AppIdentity.soliplex,
      enableDocumentFilter: false,
    );
    final on = await buildStandardKit(identity: AppIdentity.soliplex);

    expect(
      off.modules.whereType<RoomAppModule>().single.enableDocumentFilter,
      isFalse,
    );
    expect(
      on.modules.whereType<RoomAppModule>().single.enableDocumentFilter,
      isTrue,
    );
  });
}
