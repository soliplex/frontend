import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/auth/admin_status.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/per_server_cache.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart' show FakeTokenRefreshService;

class _FakeHttpClient extends Fake implements SoliplexHttpClient {}

class _FakeServerConnection extends Fake implements ServerConnection {
  _FakeServerConnection(this.api);

  @override
  final SoliplexApi api;
}

class _MockSoliplexApi extends Mock implements SoliplexApi {}

ServerEntry _entry(String serverId) {
  final api = _MockSoliplexApi();
  return ServerEntry(
    serverId: serverId,
    alias: serverId,
    serverUrl: Uri.parse('https://$serverId.example.com'),
    auth: AuthSession(refreshService: FakeTokenRefreshService()),
    httpClient: _FakeHttpClient(),
    connection: _FakeServerConnection(api),
    adminStatus: AdminStatus(api: api, serverId: serverId),
  );
}

class _Value {
  _Value(this.name, {this.throwsOnDispose = false});

  final String name;
  final bool throwsOnDispose;
  bool isDisposed = false;

  void dispose() {
    isDisposed = true;
    if (throwsOnDispose) throw StateError('teardown failed');
  }
}

void main() {
  late Signal<Map<String, ServerEntry>> servers;
  late PerServerCache<String, _Value> cache;

  setUp(() {
    servers = Signal<Map<String, ServerEntry>>({
      'srv-1': _entry('srv-1'),
      'srv-2': _entry('srv-2'),
    });
    cache = PerServerCache(
      servers: servers,
      disposeValue: (value) => value.dispose(),
      what: 'test value',
    );
  });

  tearDown(() {
    cache.dispose();
    servers.dispose();
  });

  test('keeps one value per server and key', () {
    final a = cache.putIfAbsent('srv-1', 'r1', () => _Value('a'));

    expect(cache.putIfAbsent('srv-1', 'r1', () => _Value('again')), same(a));
    expect(cache.putIfAbsent('srv-1', 'r2', () => _Value('b')).name, 'b');
    expect(cache.putIfAbsent('srv-2', 'r1', () => _Value('c')).name, 'c');
  });

  test("disposes a removed server's values, and keeps the others", () {
    final gone = cache.putIfAbsent('srv-1', 'r1', () => _Value('gone'));
    final kept = cache.putIfAbsent('srv-2', 'r1', () => _Value('kept'));

    servers.value = {'srv-2': servers.value['srv-2']!};

    expect(gone.isDisposed, isTrue);
    expect(kept.isDisposed, isFalse);
    expect(
      cache.putIfAbsent('srv-1', 'r1', () => _Value('fresh')).name,
      'fresh',
    );
    expect(cache.putIfAbsent('srv-2', 'r1', () => _Value('again')), same(kept));
  });

  test("evicting a server disposes only that server's values", () {
    final gone = cache.putIfAbsent('srv-1', 'r1', () => _Value('gone'));
    final kept = cache.putIfAbsent('srv-2', 'r1', () => _Value('kept'));

    cache.evictServer('srv-1');

    expect(gone.isDisposed, isTrue);
    expect(kept.isDisposed, isFalse);
    expect(
      cache.putIfAbsent('srv-1', 'r1', () => _Value('fresh')).name,
      'fresh',
    );
  });

  test('a value whose teardown throws is logged and strands no other', () {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    final throwing = cache.putIfAbsent(
      'srv-1',
      'r1',
      () => _Value('throwing', throwsOnDispose: true),
    );
    final next = cache.putIfAbsent('srv-1', 'r2', () => _Value('next'));

    cache.evictServer('srv-1');

    expect(throwing.isDisposed, isTrue);
    expect(next.isDisposed, isTrue);
    final record = sink.records.singleWhere((r) => r.level == LogLevel.error);
    expect(record.message, 'Failed to dispose test value');
    expect(record.attributes['serverId'], 'srv-1');
    expect(record.attributes['key'], 'r1');
  });

  test('disposing it disposes every value and refuses new ones', () {
    final a = cache.putIfAbsent('srv-1', 'r1', () => _Value('a'));
    final b = cache.putIfAbsent('srv-2', 'r1', () => _Value('b'));

    cache.dispose();

    expect([a.isDisposed, b.isDisposed], [true, true]);
    expect(
      () => cache.putIfAbsent('srv-1', 'r1', () => _Value('c')),
      throwsStateError,
    );
    servers.value = {};
    cache.dispose();
  });
}
