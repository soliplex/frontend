import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        ApiException,
        AuthException,
        MalformedResponseException,
        NotFoundException,
        PermissionDeniedException,
        RoomConfigsReloaded;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/room_reloads.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart';

void main() {
  late ServerManager manager;
  late FakeSoliplexApi fakeApi;
  late RoomReloads reloads;
  late List<String> notified;
  late MemorySink sink;

  setUp(() {
    manager = ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );
    manager.addServer(
      serverId: 'local',
      serverUrl: Uri.parse('http://localhost:8000'),
      requiresAuth: false,
    );
    fakeApi = FakeSoliplexApi();
    reloads = RoomReloads(
      entryResolver: (id) => manager.servers.value[id],
      apiResolver: (_) => fakeApi,
    );
    notified = [];
    addTearDown(reloads.listen(notified.add));
    sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
  });

  List<LogRecord> logged(LogLevel level) => sink.records
      .where((r) => r.loggerName == 'soliplex.room_reloads')
      .where((r) => r.level == level)
      .toList();

  test('answers the delta and tells listeners the rooms changed', () async {
    const delta = RoomConfigsReloaded(
      added: ['new-room'],
      removed: [],
      changed: [],
    );
    fakeApi.nextRoomReload = delta;

    final outcome = await reloads.reload('local');

    expect((outcome as RoomsReloaded).delta, same(delta));
    expect(notified, ['local']);
  });

  test('a second request while one is in flight shares its outcome', () async {
    final gate = Completer<void>();
    fakeApi.roomReloadGate = gate;

    final first = reloads.reload('local');
    final second = reloads.reload('local');
    expect(reloads.reloading.value, {'local'});

    gate.complete();
    expect(await second, isA<RoomsReloaded>());
    expect(await first, same(await second));
    expect(fakeApi.reloadRoomConfigsCallCount, 1);
    expect(reloads.reloading.value, isEmpty);
  });

  test('a 409 says the server must be restarted', () async {
    fakeApi.nextRoomReloadThrow =
        const ApiException(message: 'Conflict', statusCode: 409);

    expect(await reloads.reload('local'), isA<RoomReloadNeedsRestart>());
    expect(notified, isEmpty);
    expect(reloads.reloading.value, isEmpty);
    expect(logged(LogLevel.warning).single.attributes['serverId'], 'local');
  });

  test('a 403 is a refusal, logged with the server reason', () async {
    fakeApi.nextRoomReloadThrow = const PermissionDeniedException(
      message: 'Forbidden',
      statusCode: 403,
      serverMessage: 'not an administrator',
    );

    expect(await reloads.reload('local'), isA<RoomReloadRefused>());
    expect(notified, isEmpty);
    expect(
      logged(LogLevel.warning).single.attributes['serverMessage'],
      'not an administrator',
    );
  });

  test('a 404 says the server cannot reload rooms', () async {
    fakeApi.nextRoomReloadThrow = const NotFoundException(
      message: 'Not Found',
      resource: '/api/v1/installation/reload/rooms',
      serverMessage: 'Not Found',
    );

    expect(await reloads.reload('local'), isA<RoomReloadUnsupported>());
    expect(logged(LogLevel.error), isEmpty);
    expect(logged(LogLevel.warning).single.attributes, {
      'serverId': 'local',
      'resource': '/api/v1/installation/reload/rooms',
      'serverMessage': 'Not Found',
    });
    expect(notified, isEmpty);
  });

  test('an unreadable reply may have reloaded, so listeners are told',
      () async {
    fakeApi.nextRoomReloadThrow =
        const MalformedResponseException(message: 'not JSON');

    expect(await reloads.reload('local'), isA<RoomReloadUnreadable>());
    expect(notified, ['local']);
    expect(logged(LogLevel.error).single.attributes['serverId'], 'local');
  });

  test(
      'any other failure is logged and, as it may have reloaded, listeners '
      'are told', () async {
    const error = ApiException(message: 'boom', statusCode: 502);
    fakeApi.nextRoomReloadThrow = error;

    expect(await reloads.reload('local'), isA<RoomReloadFailed>());
    expect(notified, ['local']);
    final record = logged(LogLevel.error).single;
    expect(record.attributes['serverId'], 'local');
    expect(record.error, same(error));
    expect(record.stackTrace, isNotNull);
  });

  test('a listener that throws is logged; the reload still reports success',
      () async {
    addTearDown(reloads.listen((_) => throw StateError('listener bug')));
    final later = <String>[];
    addTearDown(reloads.listen(later.add));

    expect(await reloads.reload('local'), isA<RoomsReloaded>());
    expect(logged(LogLevel.error).single.attributes['serverId'], 'local');
    expect(later, ['local']);
  });

  test('a reload after the last one ended sends a new request', () async {
    fakeApi.nextRoomReloadThrow =
        const ApiException(message: 'boom', statusCode: 500);
    expect(await reloads.reload('local'), isA<RoomReloadFailed>());

    fakeApi.nextRoomReloadThrow = null;
    expect(await reloads.reload('local'), isA<RoomsReloaded>());
  });

  test('reloads on different servers run separately', () async {
    manager.addServer(
      serverId: 'other',
      serverUrl: Uri.parse('http://other:8000'),
      requiresAuth: false,
    );
    final gate = Completer<void>();
    final localApi = FakeSoliplexApi()..roomReloadGate = gate;
    final otherApi = FakeSoliplexApi()
      ..nextRoomReloadThrow =
          const ApiException(message: 'Conflict', statusCode: 409);
    final perServer = RoomReloads(
      entryResolver: (id) => manager.servers.value[id],
      apiResolver: (entry) => entry.serverId == 'local' ? localApi : otherApi,
    );

    final local = perServer.reload('local');
    final other = perServer.reload('other');
    expect(perServer.reloading.value, {'local', 'other'});

    expect(await other, isA<RoomReloadNeedsRestart>());
    expect(perServer.reloading.value, {'local'});
    gate.complete();
    expect(await local, isA<RoomsReloaded>());
  });

  test('a removed listener is not told', () async {
    final removed = <String>[];
    reloads.listen(removed.add)();

    await reloads.reload('local');

    expect(removed, isEmpty);
  });

  test('an expired session is marked so the lobby offers to sign in', () async {
    final entry = manager.addServer(
      serverId: 'auth-server',
      serverUrl: Uri.parse('https://api.example.com'),
    );
    entry.auth.login(
      provider: const OidcProvider(
        discoveryUrl: 'https://sso/.well-known/openid-configuration',
        clientId: 'c',
      ),
      tokens: AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    fakeApi.nextRoomReloadThrow = const AuthException(
      message: 'Unauthorized',
      statusCode: 401,
      serverMessage: 'token expired',
    );

    expect(await reloads.reload('auth-server'), isA<RoomReloadSignedOut>());
    expect(entry.auth.session.value, isA<ExpiredSession>());
    expect(notified, isEmpty);
    expect(logged(LogLevel.warning).single.attributes, {
      'serverId': 'auth-server',
      'serverMessage': 'token expired',
    });
  });

  test('throws StateError when server not found', () {
    expect(() => reloads.reload('nonexistent'), throwsStateError);
  });
}
