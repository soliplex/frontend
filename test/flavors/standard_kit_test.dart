import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_module.dart';
import 'package:soliplex_frontend/src/modules/preferences/preferences_module.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';
import 'package:soliplex_frontend/src/stores/stores_module.dart';

import '../helpers/fakes.dart';
import 'platform_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installPlatformMocks();

  test('buildStandardKit returns the coherent standard set', () async {
    final kit = await buildStandardKit(identity: AppIdentity.soliplex);

    final namespaces = kit.modules.map((m) => m.namespace).toList();
    expect(
      namespaces,
      [
        'diagnostics',
        'auth',
        'stores',
        'lobby',
        'room',
        'quiz',
        'versions',
        'preferences',
      ],
      reason: 'the standard composition, in registration order',
    );
    expect(kit.initialRoute, AppRoutes.home);
  });

  test('lobby and room share the stores module\'s instances', () async {
    final kit = await buildStandardKit(identity: AppIdentity.soliplex);
    final stores = kit.modules.whereType<StoresAppModule>().single;
    final lobby = kit.modules.whereType<LobbyAppModule>().single;
    final room = kit.modules.whereType<RoomAppModule>().single;

    expect(lobby.registry, same(stores.registry));
    expect(room.registry, same(stores.registry));
    expect(lobby.roomReadMarkers, same(stores.roomReadMarkers));
    expect(room.roomReadMarkers, same(stores.roomReadMarkers));
    expect(lobby.serverReadMarkers, same(stores.serverReadMarkers));
    expect(room.serverReadMarkers, same(stores.serverReadMarkers));
    expect(room.documentSelections, same(stores.documentSelections));
    expect(room.databaseSelections, same(stores.databaseSelections));
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

  test('with the mode stored on, restored servers are looked up at startup',
      () async {
    // Before any room opens, so a first message seldom goes out before its
    // server's profile is known.
    SharedPreferences.setMockInitialValues({
      'soliplex_has_launched': true,
      'soliplex_low_bandwidth_mode': true,
    });
    seedSecureStorage({
      'soliplex_server_local': jsonEncode(
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        ).toJson(),
      ),
    });

    final kit = await buildStandardKit(identity: AppIdentity.soliplex);

    final preference =
        kit.modules.whereType<PreferencesAppModule>().single.preference;
    expect(kit.serverManager.servers.value, isNotEmpty);
    expect(
      preference.checkingServers.value,
      kit.serverManager.servers.value.keys.toSet(),
    );
  });

  test('signedOutLandingPath never displaces the auth callback', () async {
    // Winning here would boot past a captured OIDC callback and break sign-in.
    final kit = await buildStandardKit(
      identity: AppIdentity.soliplex,
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
      signedOutLandingPath: '/welcome',
    );

    expect(kit.initialRoute, AppRoutes.authCallback);
  });

  test('signedOutLandingPath never displaces the lobby', () async {
    SharedPreferences.setMockInitialValues({'soliplex_has_launched': true});
    seedSecureStorage({
      'soliplex_server_local': jsonEncode(
        KnownServer(
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        ).toJson(),
      ),
    });

    final kit = await buildStandardKit(
      identity: AppIdentity.soliplex,
      signedOutLandingPath: '/welcome',
    );

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

  test("runs ask for the server's message profile when the stored mode is on",
      () async {
    SharedPreferences.setMockInitialValues({
      'soliplex_low_bandwidth_mode': true,
    });
    final kit = await buildStandardKit(identity: AppIdentity.soliplex);
    final api = FakeSoliplexApi()
      ..nextCreateThread = (
        ThreadInfo(id: 'thread-1', roomId: 'room-1', createdAt: DateTime(2026)),
        <String, dynamic>{},
      )
      ..nextCreateRun =
          RunInfo(id: 'run-1', threadId: 'thread-1', createdAt: DateTime(2026))
      ..sseDeliveryProfiles = const [
        SseDeliveryProfile(name: 'low_latency', strategy: 'bounded'),
        SseDeliveryProfile(name: 'low_bandwidth', strategy: 'message'),
      ];
    final stream = RecordingAgUiStreamClient();
    final connection = ServerConnection(
      serverId: 'server-1',
      api: api,
      agUiStreamClient: stream,
    );
    await kit.modules
        .whereType<PreferencesAppModule>()
        .single
        .preference
        .checkServers([connection]);
    final runtime = kit.modules
        .whereType<RoomAppModule>()
        .single
        .runtimeManager
        .getRuntime(connection);

    final session =
        await runtime.spawn(roomId: 'room-1', prompt: [const TextPart('Hi')]);
    await session.result;

    expect(stream.inputs.single.toJson()['forwardedProps'], {
      'agui_sse_delivery': 'low_bandwidth',
    });
  });
}
