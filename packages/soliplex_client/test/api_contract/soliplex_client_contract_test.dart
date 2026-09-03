// ============================================================================
// API CONTRACT TESTS - soliplex_client
// ============================================================================
//
// !! MAJOR VERSION BUMP REQUIRED !!
//
// If these tests fail or need modification due to codebase changes, it means
// the public API has changed in a breaking way. You MUST:
//
//   1. Increment the MAJOR version in pubspec.yaml (e.g., 1.0.0 -> 2.0.0)
//   2. Use a conventional commit with "BREAKING CHANGE:" in the footer
//   3. Update these tests to reflect the new API
//
// These tests exist to protect external consumers of this library. Breaking
// changes without a major version bump will break their builds.
//
// ============================================================================
//
// IMPORTANT: Only import from the public library entry point.
//
// ignore_for_file: unused_local_variable
// Redundant arguments are intentional - we test that parameters exist:
// ignore_for_file: avoid_redundant_argument_values
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'dart:typed_data';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('soliplex_client public API contract', () {
    // =========================================================================
    // Domain Models
    // =========================================================================

    group('Room', () {
      test('constructor with all parameters', () {
        const room = Room(
          id: 'room-1',
          name: 'Test Room',
          description: 'A test room',
          metadata: {'key': 'value'},
          quizzes: {'quiz-1': 'Quiz One'},
        );

        expect(room.id, isA<String>());
        expect(room.name, isA<String>());
        expect(room.description, isA<String>());
        expect(room.metadata, isA<Map<String, dynamic>>());
        expect(room.quizzes, isA<Map<String, String>>());
        expect(room.quizIds, isA<List<String>>());
        expect(room.hasDescription, isA<bool>());
        expect(room.hasQuizzes, isA<bool>());
      });

      test('copyWith signature', () {
        const room = Room(id: 'room-1', name: 'Test');
        final copied = room.copyWith(
          id: 'room-2',
          name: 'New',
          description: 'desc',
          metadata: {},
          quizzes: {},
        );
        expect(copied, isA<Room>());
      });
    });

    group('ThreadInfo', () {
      test('constructor with all parameters', () {
        final thread = ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          createdAt: DateTime.now(),
          initialRunId: 'run-1',
          name: 'Thread',
          description: 'A thread',
          metadata: {'key': 'value'},
        );

        expect(thread.id, isA<String>());
        expect(thread.roomId, isA<String>());
        expect(thread.initialRunId, isA<String>());
        expect(thread.name, isA<String>());
        expect(thread.description, isA<String>());
        expect(thread.createdAt, isA<DateTime>());
        expect(thread.metadata, isA<Map<String, dynamic>>());
        expect(thread.hasInitialRun, isA<bool>());
        expect(thread.hasName, isA<bool>());
        expect(thread.hasDescription, isA<bool>());
      });

      test('copyWith signature', () {
        final thread = ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          createdAt: DateTime.now(),
        );
        final copied = thread.copyWith(
          id: 'thread-2',
          roomId: 'room-2',
          initialRunId: 'run-1',
          name: 'name',
          description: 'desc',
          createdAt: DateTime.now(),
          metadata: {},
        );
        expect(copied, isA<ThreadInfo>());
      });
    });

    group('RunInfo', () {
      test('constructor with all parameters', () {
        final run = RunInfo(
          id: 'run-1',
          threadId: 'thread-1',
          createdAt: DateTime.now(),
          label: 'Run 1',
          completion: const NotCompleted(),
          status: RunStatus.pending,
          metadata: {'key': 'value'},
        );

        expect(run.id, isA<String>());
        expect(run.threadId, isA<String>());
        expect(run.label, isA<String>());
        expect(run.createdAt, isA<DateTime>());
        expect(run.completion, isA<CompletionTime>());
        expect(run.status, isA<RunStatus>());
        expect(run.metadata, isA<Map<String, dynamic>>());
        expect(run.hasLabel, isA<bool>());
        expect(run.isCompleted, isA<bool>());
      });

      test('copyWith signature', () {
        final run = RunInfo(
          id: 'run-1',
          threadId: 'thread-1',
          createdAt: DateTime.now(),
        );
        final copied = run.copyWith(
          id: 'run-2',
          threadId: 'thread-2',
          label: 'label',
          createdAt: DateTime.now(),
          completion: CompletedAt(DateTime(2024)),
          status: RunStatus.completed,
          metadata: {},
        );
        expect(copied, isA<RunInfo>());
      });
    });

    group('CompletionTime sealed class', () {
      test('NotCompleted', () {
        const completion = NotCompleted();
        expect(completion, isA<CompletionTime>());
      });

      test('CompletedAt', () {
        final completion = CompletedAt(DateTime.now());
        expect(completion, isA<CompletionTime>());
        expect(completion.time, isA<DateTime>());
      });
    });

    group('RunStatus enum', () {
      test('all values accessible', () {
        expect(RunStatus.pending, isA<RunStatus>());
        expect(RunStatus.running, isA<RunStatus>());
        expect(RunStatus.completed, isA<RunStatus>());
        expect(RunStatus.failed, isA<RunStatus>());
        expect(RunStatus.cancelled, isA<RunStatus>());
        expect(RunStatus.unknown, isA<RunStatus>());
      });
    });

    group('ChatMessage sealed class hierarchy', () {
      test('ChatUser enum', () {
        expect(ChatUser.user, isA<ChatUser>());
        expect(ChatUser.assistant, isA<ChatUser>());
        expect(ChatUser.system, isA<ChatUser>());
      });

      test('TextMessage', () {
        final msg = TextMessage(
          id: 'msg-1',
          user: ChatUser.assistant,
          createdAt: DateTime.now(),
          text: 'Hello',
          thinkingText: '',
        );

        expect(msg, isA<ChatMessage>());
        expect(msg.id, isA<String>());
        expect(msg.user, isA<ChatUser>());
        expect(msg.createdAt, isA<DateTime>());
        expect(msg.text, isA<String>());
        expect(msg.thinkingText, isA<String>());
        expect(msg.hasThinkingText, isA<bool>());
      });

      test('TextMessage.create factory', () {
        final msg = TextMessage.create(
          id: 'msg-1',
          user: ChatUser.user,
          text: 'Hello',
        );
        expect(msg, isA<TextMessage>());
      });

      test('TextMessage.copyWith', () {
        final msg = TextMessage.create(
          id: 'msg-1',
          user: ChatUser.user,
          text: 'Hello',
        );
        final copied = msg.copyWith(
          id: 'msg-2',
          user: ChatUser.assistant,
          createdAt: DateTime.now(),
          text: 'Hi',
          thinkingText: 'thinking',
        );
        expect(copied, isA<TextMessage>());
      });

      test('ErrorMessage', () {
        final msg = ErrorMessage(
          id: 'err-1',
          createdAt: DateTime.now(),
          errorText: 'Error occurred',
        );

        expect(msg, isA<ChatMessage>());
        expect(msg.errorText, isA<String>());
        expect(msg.user, equals(ChatUser.system));
      });

      test('ErrorMessage.create factory', () {
        final msg = ErrorMessage.create(id: 'err-1', message: 'Error');
        expect(msg, isA<ErrorMessage>());
      });

      test('ToolCallMessage', () {
        final msg = ToolCallMessage(
          id: 'tool-msg-1',
          createdAt: DateTime.now(),
          toolCalls: const [],
        );

        expect(msg, isA<ChatMessage>());
        expect(msg.toolCalls, isA<List<ToolCallInfo>>());
        expect(msg.user, equals(ChatUser.assistant));
      });

      test('ToolCallMessage.create factory', () {
        final msg = ToolCallMessage.create(id: 'tool-msg-1', toolCalls: []);
        expect(msg, isA<ToolCallMessage>());
      });

      test('GenUiMessage', () {
        final msg = GenUiMessage(
          id: 'genui-1',
          createdAt: DateTime.now(),
          widgetName: 'MyWidget',
          data: {'key': 'value'},
        );

        expect(msg, isA<ChatMessage>());
        expect(msg.widgetName, isA<String>());
        expect(msg.data, isA<Map<String, dynamic>>());
      });

      test('GenUiMessage.create factory', () {
        final msg = GenUiMessage.create(
          id: 'genui-1',
          widgetName: 'Widget',
          data: {},
        );
        expect(msg, isA<GenUiMessage>());
      });

      test('LoadingMessage', () {
        final msg = LoadingMessage(id: 'loading-1', createdAt: DateTime.now());
        expect(msg, isA<ChatMessage>());
      });

      test('LoadingMessage.create factory', () {
        final msg = LoadingMessage.create(id: 'loading-1');
        expect(msg, isA<LoadingMessage>());
      });
    });

    group('ToolCallInfo', () {
      test('constructor with all parameters', () {
        const info = ToolCallInfo(
          id: 'call-1',
          name: 'myTool',
          arguments: '{"key": "value"}',
          status: ToolCallStatus.pending,
          result: 'result',
        );

        expect(info.id, isA<String>());
        expect(info.name, isA<String>());
        expect(info.arguments, isA<String>());
        expect(info.status, isA<ToolCallStatus>());
        expect(info.result, isA<String>());
        expect(info.hasArguments, isA<bool>());
        expect(info.hasResult, isA<bool>());
      });

      test('copyWith signature', () {
        const info = ToolCallInfo(id: 'call-1', name: 'tool');
        final copied = info.copyWith(
          id: 'call-2',
          name: 'newTool',
          arguments: '{}',
          status: ToolCallStatus.completed,
          result: 'done',
        );
        expect(copied, isA<ToolCallInfo>());
      });
    });

    group('ToolCallStatus enum', () {
      test('all values accessible', () {
        expect(ToolCallStatus.streaming, isA<ToolCallStatus>());
        expect(ToolCallStatus.pending, isA<ToolCallStatus>());
        expect(ToolCallStatus.executing, isA<ToolCallStatus>());
        expect(ToolCallStatus.completed, isA<ToolCallStatus>());
        expect(ToolCallStatus.failed, isA<ToolCallStatus>());
      });
    });

    // =========================================================================
    // Errors
    // =========================================================================

    group('Exception hierarchy', () {
      test('SoliplexException is abstract base', () {
        // Cannot instantiate abstract class, but can check subtypes
        const auth = AuthException(message: 'auth failed');
        expect(auth, isA<SoliplexException>());
        expect(auth.message, isA<String>());
        expect(auth.originalError, isNull);
        expect(auth.stackTrace, isNull);
      });

      test('AuthException', () {
        const ex = AuthException(
          message: 'Unauthorized',
          statusCode: 401,
          serverMessage: 'Invalid token',
        );

        expect(ex, isA<SoliplexException>());
        expect(ex.message, isA<String>());
        expect(ex.statusCode, isA<int?>());
        expect(ex.serverMessage, isA<String?>());
      });

      test('NetworkException', () {
        const ex = NetworkException(
          message: 'Connection failed',
          isTimeout: true,
        );

        expect(ex, isA<SoliplexException>());
        expect(ex.message, isA<String>());
        expect(ex.isTimeout, isA<bool>());
      });

      test('ApiException', () {
        const ex = ApiException(
          message: 'Server error',
          statusCode: 500,
          serverMessage: 'Internal error',
          body: '{"error": "details"}',
        );

        expect(ex, isA<SoliplexException>());
        expect(ex.message, isA<String>());
        expect(ex.statusCode, isA<int>());
        expect(ex.serverMessage, isA<String?>());
        expect(ex.body, isA<String?>());
      });

      test('NotFoundException', () {
        const ex = NotFoundException(
          message: 'Not found',
          resource: '/api/rooms/123',
          serverMessage: 'Room not found',
        );

        expect(ex, isA<SoliplexException>());
        expect(ex.message, isA<String>());
        expect(ex.resource, isA<String?>());
        expect(ex.serverMessage, isA<String?>());
      });

      test('CancelledException', () {
        const ex = CancelledException(reason: 'User cancelled');

        expect(ex, isA<SoliplexException>());
        expect(ex.message, isA<String>());
        expect(ex.reason, isA<String?>());
      });
    });

    // =========================================================================
    // HTTP Layer
    // =========================================================================

    group('HttpResponse', () {
      test('constructor with all parameters', () {
        final response = HttpResponse(
          statusCode: 200,
          bodyBytes: Uint8List.fromList([]),
          headers: {'content-type': 'application/json'},
          reasonPhrase: 'OK',
        );

        expect(response.statusCode, isA<int>());
        expect(response.bodyBytes, isA<Uint8List>());
        expect(response.headers, isA<Map<String, String>>());
        expect(response.reasonPhrase, isA<String?>());
        expect(response.body, isA<String>());
        expect(response.isSuccess, isA<bool>());
        expect(response.isRedirect, isA<bool>());
        expect(response.isClientError, isA<bool>());
        expect(response.isServerError, isA<bool>());
        expect(response.contentType, isA<String?>());
        expect(response.contentLength, isA<int?>());
      });
    });

    group('SoliplexHttpClient interface', () {
      test('DartHttpClient implements SoliplexHttpClient', () {
        final client = DartHttpClient(
          defaultTimeout: const Duration(seconds: 30),
        );

        expect(client, isA<SoliplexHttpClient>());

        // Verify method signatures exist (don't call - would make network req)
        expect(client.request, isA<Function>());
        expect(client.requestStream, isA<Function>());
        expect(client.close, isA<Function>());

        client.close();
      });

      test('DartHttpClient defaultTimeout property', () {
        final client = DartHttpClient(
          defaultTimeout: const Duration(seconds: 60),
        );
        expect(client.defaultTimeout, equals(const Duration(seconds: 60)));
        client.close();
      });
    });

    group('ObservableHttpClient', () {
      test('constructor with all parameters', () {
        final inner = DartHttpClient();
        final observable = ObservableHttpClient(
          client: inner,
          observers: [],
          generateRequestId: () => 'test-id',
        );

        expect(observable, isA<SoliplexHttpClient>());
        observable.close();
      });
    });

    group('HttpTransport', () {
      test('constructor with all parameters', () {
        final client = DartHttpClient();
        final transport = HttpTransport(
          client: client,
          defaultTimeout: const Duration(seconds: 30),
        );

        expect(transport, isA<HttpTransport>());
        expect(transport.defaultTimeout, isA<Duration>());

        // Verify method signatures
        expect(transport.request, isA<Function>());
        expect(transport.requestStream, isA<Function>());
        expect(transport.close, isA<Function>());

        transport.close();
      });
    });

    group('HttpObserver and events', () {
      test('HttpEvent base class properties', () {
        final event = HttpRequestEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          method: 'GET',
          uri: Uri.parse('https://example.com'),
          headers: {},
        );

        expect(event.requestId, isA<String>());
        expect(event.timestamp, isA<DateTime>());
      });

      test('HttpRequestEvent', () {
        final event = HttpRequestEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          method: 'GET',
          uri: Uri.parse('https://example.com'),
          headers: {'Authorization': 'Bearer token'},
        );

        expect(event, isA<HttpEvent>());
        expect(event.method, isA<String>());
        expect(event.uri, isA<Uri>());
        expect(event.headers, isA<Map<String, String>>());
      });

      test('HttpResponseEvent', () {
        final event = HttpResponseEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          statusCode: 200,
          duration: const Duration(milliseconds: 100),
          bodySize: 1024,
          reasonPhrase: 'OK',
        );

        expect(event, isA<HttpEvent>());
        expect(event.statusCode, isA<int>());
        expect(event.duration, isA<Duration>());
        expect(event.bodySize, isA<int>());
        expect(event.reasonPhrase, isA<String?>());
        expect(event.isSuccess, isA<bool>());
      });

      test('HttpErrorEvent', () {
        final event = HttpErrorEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          method: 'GET',
          uri: Uri.parse('https://example.com'),
          exception: const NetworkException(message: 'Failed'),
          duration: const Duration(milliseconds: 50),
        );

        expect(event, isA<HttpEvent>());
        expect(event.method, isA<String>());
        expect(event.uri, isA<Uri>());
        expect(event.exception, isA<SoliplexException>());
        expect(event.duration, isA<Duration>());
      });

      test('HttpStreamStartEvent', () {
        final event = HttpStreamStartEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          method: 'GET',
          uri: Uri.parse('https://example.com'),
        );

        expect(event, isA<HttpEvent>());
        expect(event.method, isA<String>());
        expect(event.uri, isA<Uri>());
      });

      test('HttpStreamEndEvent', () {
        final event = HttpStreamEndEvent(
          requestId: 'req-1',
          timestamp: DateTime.now(),
          bytesReceived: 2048,
          duration: const Duration(seconds: 5),
          error: null,
        );

        expect(event, isA<HttpEvent>());
        expect(event.bytesReceived, isA<int>());
        expect(event.duration, isA<Duration>());
        expect(event.error, isA<SoliplexException?>());
        expect(event.isSuccess, isA<bool>());
      });
    });

    // =========================================================================
    // Utils
    // =========================================================================

    group('UrlBuilder', () {
      test('constructor and baseUrl', () {
        final builder = UrlBuilder('https://api.example.com/v1');

        expect(builder, isA<UrlBuilder>());
        expect(builder.baseUrl, isA<String>());
      });

      test('build method with all parameters', () {
        final builder = UrlBuilder('https://api.example.com/v1');

        final uri = builder.build(
          path: 'rooms',
          pathSegments: ['123', 'threads'],
          queryParameters: {'limit': '10'},
        );

        expect(uri, isA<Uri>());
      });
    });

    // =========================================================================
    // API Layer
    // =========================================================================

    group('SoliplexApi', () {
      test('constructor signature', () {
        final client = DartHttpClient();
        final transport = HttpTransport(client: client);
        final urlBuilder = UrlBuilder('https://api.example.com/v1');

        final api = SoliplexApi(
          transport: transport,
          urlBuilder: urlBuilder,
          onWarning: (msg) {},
        );

        expect(api, isA<SoliplexApi>());

        // Verify all public methods exist
        expect(api.getRooms, isA<Function>());
        expect(api.getRoom, isA<Function>());
        expect(api.getThreads, isA<Function>());
        expect(api.getThread, isA<Function>());
        expect(api.createThread, isA<Function>());
        expect(api.deleteThread, isA<Function>());
        expect(api.createRun, isA<Function>());
        expect(api.getRun, isA<Function>());
        expect(api.getThreadHistory, isA<Function>());
        expect(api.getQuiz, isA<Function>());
        expect(api.submitQuizAnswer, isA<Function>());
        expect(api.getBackendVersionInfo, isA<Function>());
        expect(api.close, isA<Function>());

        api.close();
      });
    });

    // =========================================================================
    // Consumer Simulation
    // =========================================================================

    group('consumer simulation: typical API client setup', () {
      test('create full HTTP stack', () {
        // Simulates how an external project would set up the client
        final httpClient = DartHttpClient(
          defaultTimeout: const Duration(seconds: 30),
        );

        final observableClient = ObservableHttpClient(
          client: httpClient,
          observers: [],
        );

        final transport = HttpTransport(
          client: observableClient,
          defaultTimeout: const Duration(seconds: 60),
        );

        final urlBuilder = UrlBuilder('https://api.myapp.com/v1');

        final api = SoliplexApi(transport: transport, urlBuilder: urlBuilder);

        expect(api, isA<SoliplexApi>());

        api.close();
      });

      test('create domain models for testing', () {
        // External project creating test fixtures
        const room = Room(
          id: 'test-room',
          name: 'Test Room',
          description: 'For testing',
          quizzes: {'q1': 'Quiz 1'},
        );

        final thread = ThreadInfo(
          id: 'test-thread',
          roomId: room.id,
          createdAt: DateTime.now(),
        );

        final run = RunInfo(
          id: 'test-run',
          threadId: thread.id,
          createdAt: DateTime.now(),
          status: RunStatus.completed,
          completion: CompletedAt(DateTime.now()),
        );

        expect(room.hasQuizzes, isTrue);
        expect(thread.roomId, equals(room.id));
        expect(run.isCompleted, isTrue);
      });

      test('handle exceptions', () {
        // External project handling all exception types
        void handleError(SoliplexException ex) {
          switch (ex) {
            case AuthException():
              // Redirect to login
              expect(ex.statusCode, isA<int?>());
            case NetworkException():
              // Show retry button
              expect(ex.isTimeout, isA<bool>());
            case NotFoundException():
              // Navigate back
              expect(ex.resource, isA<String?>());
            case ApiException():
              // Show error message
              expect(ex.statusCode, isA<int>());
            case CancelledException():
              // Silent handling
              expect(ex.reason, isA<String?>());
          }
        }

        handleError(const AuthException(message: 'test', statusCode: 401));
        handleError(const NetworkException(message: 'test', isTimeout: true));
        handleError(const NotFoundException(message: 'test'));
        handleError(const ApiException(message: 'test', statusCode: 500));
        handleError(const CancelledException());
      });
    });
  });
}
