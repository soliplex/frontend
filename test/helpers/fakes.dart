import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        HttpTransport,
        Quiz,
        QuizAnswerResult,
        RagDocument,
        SoliplexApi,
        UrlBuilder;
import 'package:soliplex_logging/soliplex_logging.dart' show LoggerFactory;

import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';

/// Minimal HTTP client with configurable responses.
///
/// By default, throws [UnimplementedError] on every call.
/// Set [onRequest] to return controlled responses for testing.
class FakeHttpClient extends SoliplexHttpClient {
  bool closeCalled = false;

  Future<HttpResponse> Function(String method, Uri uri)? onRequest;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    if (onRequest != null) return onRequest!(method, uri);
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

/// Fake AuthFlow for testing consumers that depend on AuthFlow.
class FakeAuthFlow implements AuthFlow {
  AuthResult? nextResult;
  AuthException? nextError;
  bool throwRedirectInitiated = false;
  bool endSessionCalled = false;
  String? lastEndSessionDiscoveryUrl;

  @override
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
  }) async {
    if (throwRedirectInitiated) throw const AuthRedirectInitiated();
    if (nextError != null) throw nextError!;
    if (nextResult != null) return nextResult!;
    throw StateError('FakeAuthFlow: set nextResult or nextError');
  }

  @override
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  }) async {
    endSessionCalled = true;
    lastEndSessionDiscoveryUrl = discoveryUrl;
  }
}

/// AuthFlow that calls a callback during endSession for order verification.
class RecordingAuthFlow implements AuthFlow {
  RecordingAuthFlow({this.onEndSession});

  final void Function()? onEndSession;
  bool endSessionCalled = false;
  String? lastEndSessionEndpoint;

  @override
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
  }) async {
    throw StateError('RecordingAuthFlow: authenticate not configured');
  }

  @override
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  }) async {
    endSessionCalled = true;
    lastEndSessionEndpoint = endSessionEndpoint;
    onEndSession?.call();
  }
}

/// SoliplexApi with a controllable getRooms response.
///
/// All other methods throw [UnimplementedError].
class FakeSoliplexApi extends SoliplexApi {
  FakeSoliplexApi()
      : super(
          transport: HttpTransport(client: FakeHttpClient()),
          urlBuilder: UrlBuilder('https://fake.example.com/api/v1'),
        );

  List<Room>? nextRooms;
  Room? nextRoom;
  Exception? nextError;

  List<RagDocument>? nextDocuments;
  Exception? nextDocumentsError;
  String? nextMcpToken;
  Exception? nextMcpTokenError;

  List<ThreadInfo>? nextThreads;
  Exception? nextThreadsError;
  ThreadHistory? nextThreadHistory;
  Exception? nextThreadHistoryError;
  (ThreadInfo, Map<String, dynamic>)? nextCreateThread;
  Exception? nextCreateThreadError;

  @override
  Future<List<Room>> getRooms({CancelToken? cancelToken}) async {
    if (nextError != null) throw nextError!;
    if (nextRooms != null) return nextRooms!;
    throw StateError(
        'FakeSoliplexApi: set nextRooms or nextError before calling');
  }

  @override
  Future<Room> getRoom(String roomId, {CancelToken? cancelToken}) async {
    if (nextError != null) throw nextError!;
    if (nextRoom != null) return nextRoom!;
    throw StateError(
        'FakeSoliplexApi: set nextRoom or nextError before calling');
  }

  @override
  Future<List<ThreadInfo>> getThreads(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    if (nextThreadsError != null) throw nextThreadsError!;
    if (nextThreads != null) return nextThreads!;
    throw StateError('FakeSoliplexApi: set nextThreads or nextThreadsError');
  }

  @override
  Future<ThreadHistory> getThreadHistory(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
  }) async {
    if (nextThreadHistoryError != null) throw nextThreadHistoryError!;
    if (nextThreadHistory != null) return nextThreadHistory!;
    throw StateError(
        'FakeSoliplexApi: set nextThreadHistory or nextThreadHistoryError');
  }

  @override
  Future<(ThreadInfo, Map<String, dynamic>)> createThread(
    String roomId, {
    String? name,
    CancelToken? cancelToken,
  }) async {
    if (nextCreateThreadError != null) throw nextCreateThreadError!;
    if (nextCreateThread != null) return nextCreateThread!;
    throw StateError(
      'FakeSoliplexApi: set nextCreateThread or nextCreateThreadError',
    );
  }

  @override
  Future<List<RagDocument>> getDocuments(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    if (nextDocumentsError != null) throw nextDocumentsError!;
    return nextDocuments ?? const [];
  }

  @override
  Future<String> getMcpToken(String roomId, {CancelToken? cancelToken}) async {
    if (nextMcpTokenError != null) throw nextMcpTokenError!;
    return nextMcpToken ?? 'fake-token';
  }

  Quiz? nextQuiz;
  Exception? nextQuizError;
  QuizAnswerResult? nextQuizAnswerResult;
  Exception? nextQuizAnswerError;
  Object? nextQuizAnswerThrowable;

  @override
  Future<Quiz> getQuiz(
    String roomId,
    String quizId, {
    CancelToken? cancelToken,
  }) async {
    if (nextQuizError != null) throw nextQuizError!;
    if (nextQuiz != null) return nextQuiz!;
    throw StateError('FakeSoliplexApi: set nextQuiz or nextQuizError');
  }

  Completer<QuizAnswerResult>? submitQuizAnswerCompleter;
  int submitQuizAnswerCallCount = 0;

  @override
  Future<QuizAnswerResult> submitQuizAnswer(
    String roomId,
    String quizId,
    String questionId,
    String answer, {
    CancelToken? cancelToken,
  }) async {
    submitQuizAnswerCallCount++;
    if (submitQuizAnswerCompleter != null) {
      return submitQuizAnswerCompleter!.future;
    }
    if (nextQuizAnswerThrowable != null) throw nextQuizAnswerThrowable!;
    if (nextQuizAnswerError != null) throw nextQuizAnswerError!;
    if (nextQuizAnswerResult != null) return nextQuizAnswerResult!;
    throw StateError(
      'FakeSoliplexApi: set nextQuizAnswerResult or nextQuizAnswerError',
    );
  }
}

/// AgUiStreamClient that throws [UnimplementedError] for all calls.
///
/// Sufficient for constructing a [ServerConnection] in tests that don't
/// exercise streaming.
class FakeAgUiStreamClient extends AgUiStreamClient {
  FakeAgUiStreamClient()
      : super(
          httpTransport: HttpTransport(client: FakeHttpClient()),
          urlBuilder: UrlBuilder('https://fake.example.com/api/v1'),
        );
}

/// Logger for tests. Uses soliplex_logging's LogManager.
Logger testLogger() {
  return LogManager.instance.getLogger('test');
}

/// PlatformConstraints for tests (native-like behavior).
class TestPlatformConstraints implements PlatformConstraints {
  @override
  bool get supportsParallelExecution => true;
  @override
  bool get supportsAsyncMode => false;
  @override
  int get maxConcurrentBridges => 10;
  @override
  bool get supportsReentrantInterpreter => true;
  @override
  int get maxConcurrentSessions => maxConcurrentBridges;
}

/// In-memory server storage for tests.
class InMemoryServerStorage implements ServerStorage {
  final Map<String, PersistedServer> _store = {};
  int saveCount = 0;

  @override
  Future<void> save(String serverId, PersistedServer data) async {
    saveCount++;
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
