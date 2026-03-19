import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/token_storage.dart';

/// Minimal HTTP client that throws on every call.
class FakeHttpClient extends SoliplexHttpClient {
  bool closeCalled = false;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    throw UnimplementedError('FakeHttpClient.request');
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) {
    throw UnimplementedError('FakeHttpClient.requestStream');
  }

  @override
  void close() {
    closeCalled = true;
  }
}

/// Token refresh service backed by a FakeHttpClient.
/// Override [nextResult] to control test outcomes.
class FakeTokenRefreshService extends TokenRefreshService {
  FakeTokenRefreshService() : super(httpClient: FakeHttpClient());

  TokenRefreshResult? nextResult;

  @override
  Future<TokenRefreshResult> refresh({
    required String discoveryUrl,
    required String refreshToken,
    required String clientId,
  }) async {
    if (nextResult != null) return nextResult!;
    throw StateError('FakeTokenRefreshService: set nextResult before calling');
  }
}

/// HTTP observer that collects events for assertions.
class FakeHttpObserver implements HttpObserver {
  final List<HttpEvent> events = [];

  @override
  void onRequest(HttpRequestEvent event) => events.add(event);
  @override
  void onResponse(HttpResponseEvent event) => events.add(event);
  @override
  void onError(HttpErrorEvent event) => events.add(event);
  @override
  void onStreamStart(HttpStreamStartEvent event) => events.add(event);
  @override
  void onStreamEnd(HttpStreamEndEvent event) => events.add(event);
}

/// In-memory token storage for tests.
class InMemoryTokenStorage implements TokenStorage {
  final Map<String, PersistedServer> _store = {};

  @override
  Future<void> save(String serverId, PersistedServer data) async {
    _store[serverId] = data;
  }

  @override
  Future<void> delete(String serverId) async {
    _store.remove(serverId);
  }

  @override
  Future<Map<String, PersistedServer>> loadAll() async {
    return Map.unmodifiable(_store);
  }
}
