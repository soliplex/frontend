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

  late ServerEntry srv1;
  late ServerEntry srv2;

  setUp(() {
    srv1 = _entry('srv-1');
    srv2 = _entry('srv-2');
    servers = Signal<Map<String, ServerEntry>>({'srv-1': srv1, 'srv-2': srv2});
    cache = PerServerCache(
      servers: servers,
      disposeValue: (value) => value.dispose(),
    );
  });

  tearDown(() {
    cache.dispose();
    servers.dispose();
  });

  test('keeps one value per server and key', () {
    final a = cache.putIfAbsent(srv1, 'r1', () => _Value('a'));

    expect(cache.putIfAbsent(srv1, 'r1', () => _Value('again')), same(a));
    expect(cache.putIfAbsent(srv1, 'r2', () => _Value('b')).name, 'b');
    expect(cache.putIfAbsent(srv2, 'r1', () => _Value('c')).name, 'c');
  });

  test("disposes a removed server's values, and keeps the others", () {
    final gone = cache.putIfAbsent(srv1, 'r1', () => _Value('gone'));
    final kept = cache.putIfAbsent(srv2, 'r1', () => _Value('kept'));

    servers.value = {'srv-2': srv2};

    expect(gone.isDisposed, isTrue);
    expect(kept.isDisposed, isFalse);
    expect(
      cache.putIfAbsent(srv1, 'r1', () => _Value('fresh')).name,
      'fresh',
    );
    expect(cache.putIfAbsent(srv2, 'r1', () => _Value('again')), same(kept));
  });

  test("evicting a server disposes only that server's values", () {
    final gone = cache.putIfAbsent(srv1, 'r1', () => _Value('gone'));
    final kept = cache.putIfAbsent(srv2, 'r1', () => _Value('kept'));

    cache.evictServer('srv-1');

    expect(gone.isDisposed, isTrue);
    expect(kept.isDisposed, isFalse);
    expect(
      cache.putIfAbsent(srv1, 'r1', () => _Value('fresh')).name,
      'fresh',
    );
  });

  test('a value whose teardown throws is logged and strands no other', () {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    final throwing = cache.putIfAbsent(
      srv1,
      'r1',
      () => _Value('throwing', throwsOnDispose: true),
    );
    final next = cache.putIfAbsent(srv1, 'r2', () => _Value('next'));

    cache.evictServer('srv-1');

    expect(throwing.isDisposed, isTrue);
    expect(next.isDisposed, isTrue);
    final record = sink.records.singleWhere((r) => r.level == LogLevel.error);
    expect(record.message, 'Failed to dispose _Value');
    expect(record.attributes['serverId'], 'srv-1');
    expect(record.attributes['key'], 'r1');
    expect(record.attributes['failure'], isNotNull);
    expect(record.error, isNull, reason: 'any teardown may carry anything');
  });

  test('a value made for a removed server is not served once it is back', () {
    servers.value = {'srv-2': srv2};
    // A screen still showing the removed server asks once more.
    final stale = cache.putIfAbsent(srv1, 'r1', () => _Value('stale'));

    final readded = _entry('srv-1');
    servers.value = {'srv-1': readded, 'srv-2': srv2};

    expect(stale.isDisposed, isTrue);
    expect(
      cache.putIfAbsent(readded, 'r1', () => _Value('fresh')).name,
      'fresh',
    );
  });

  test("an entry no longer listed leaves the listed entry's value alone", () {
    final readded = _entry('srv-1');
    servers.value = {'srv-1': readded, 'srv-2': srv2};
    final live = cache.putIfAbsent(readded, 'r1', () => _Value('live'));

    // A screen still holding the entry from before asks too.
    final stale = cache.putIfAbsent(srv1, 'r1', () => _Value('stale'));

    expect(stale, isNot(same(live)));
    expect(live.isDisposed, isFalse);
    expect(cache.putIfAbsent(readded, 'r1', () => _Value('again')), same(live));

    servers.value = {'srv-1': readded};
    expect(stale.isDisposed, isTrue, reason: 'its entry is not listed');
    expect(live.isDisposed, isFalse);
  });

  test('a teardown that throws while the cache is disposed strands no other',
      () {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    final throwing = cache.putIfAbsent(
      srv1,
      'r1',
      () => _Value('throwing', throwsOnDispose: true),
    );
    final next = cache.putIfAbsent(srv2, 'r1', () => _Value('next'));

    cache.dispose();

    expect([throwing.isDisposed, next.isDisposed], [true, true]);
    expect(
      sink.records.where((r) => r.level == LogLevel.error),
      hasLength(1),
    );
  });

  test('disposing it disposes every value and refuses new ones', () {
    final a = cache.putIfAbsent(srv1, 'r1', () => _Value('a'));
    final b = cache.putIfAbsent(srv2, 'r1', () => _Value('b'));

    cache.dispose();

    expect([a.isDisposed, b.isDisposed], [true, true]);
    expect(
      () => cache.putIfAbsent(srv1, 'r1', () => _Value('c')),
      throwsStateError,
    );
    servers.value = {};
    cache.dispose();
  });
}
