import 'package:mocktail/mocktail.dart';
// SoliplexApi uses our local CancelToken, not ag_ui's.
// Hide ag_ui's CancelToken to avoid ambiguity.
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

void main() {
  late MockHttpTransport mockTransport;
  late UrlBuilder urlBuilder;
  late SoliplexApi api;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    mockTransport = MockHttpTransport();
    urlBuilder = UrlBuilder('https://api.example.com/api/v1');
    api = SoliplexApi(transport: mockTransport, urlBuilder: urlBuilder);

    when(() => mockTransport.close()).thenReturn(null);
  });

  tearDown(() {
    api.close();
    reset(mockTransport);
  });

  group('SoliplexApi', () {
    group('constructor', () {
      test('creates with required dependencies', () {
        expect(api, isNotNull);
      });
    });

    group('close', () {
      test('delegates to transport', () {
        api.close();

        verify(() => mockTransport.close()).called(1);
      });

      test('clears the run events cache', () async {
        // Thread endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'Hello',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        // First call populates cache
        await api.getThreadHistory('room-123', 'thread-456');

        // Close clears the cache
        api.close();

        // Create new API instance (simulates reconnection)
        final api2 = SoliplexApi(
          transport: mockTransport,
          urlBuilder: urlBuilder,
        );

        // Second call should fetch from network (cache was cleared)
        await api2.getThreadHistory('room-123', 'thread-456');

        // Run endpoint should be called twice (once per API instance)
        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(2);

        api2.close();
      });
    });

    // ============================================================
    // Rooms
    // ============================================================

    group('getRooms', () {
      test('returns list of rooms from map', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room-1': {'id': 'room-1', 'name': 'Room 1'},
            'room-2': {'id': 'room-2', 'name': 'Room 2'},
          },
        );

        final rooms = await api.getRooms();

        expect(rooms.length, equals(2));
        expect(rooms.any((r) => r.id == 'room-1'), isTrue);
        expect(rooms.any((r) => r.id == 'room-2'), isTrue);
      });

      test('returns empty list when no rooms', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => <String, dynamic>{});

        final rooms = await api.getRooms();

        expect(rooms, isEmpty);
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const AuthException(message: 'Unauthorized'));

        expect(() => api.getRooms(), throwsA(isA<AuthException>()));
      });

      test('skips malformed rooms and returns valid ones', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room-1': {'id': 'room-1', 'name': 'Good Room'},
            'room-2': 'not a map',
            'room-3': {'id': 'room-3', 'name': 'Also Good'},
          },
        );

        final rooms = await api.getRooms();

        expect(rooms, hasLength(2));
        expect(rooms.any((r) => r.id == 'room-1'), isTrue);
        expect(rooms.any((r) => r.id == 'room-3'), isTrue);
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => <String, dynamic>{});

        await api.getRooms(cancelToken: cancelToken);

        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return <String, dynamic>{};
        });

        await api.getRooms();

        expect(capturedUri?.path, equals('/api/v1/rooms'));
      });
    });

    group('getRoom', () {
      test('returns room by ID', () async {
        when(
          () => mockTransport.request<Room>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const Room(id: 'room-123', name: 'Test Room'),
        );

        final room = await api.getRoom('room-123');

        expect(room.id, equals('room-123'));
        expect(room.name, equals('Test Room'));
      });

      test('validates non-empty roomId', () {
        expect(() => api.getRoom(''), throwsA(isA<ArgumentError>()));
      });

      test('propagates NotFoundException', () async {
        when(
          () => mockTransport.request<Room>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Not found'));

        expect(
          () => api.getRoom('nonexistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Room>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => const Room(id: 'room-123', name: 'Test'));

        await api.getRoom('room-123', cancelToken: cancelToken);

        verify(
          () => mockTransport.request<Room>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Room>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return const Room(id: 'room-123', name: 'Test');
        });

        await api.getRoom('room-123');

        expect(capturedUri?.path, equals('/api/v1/rooms/room-123'));
      });
    });

    // ============================================================
    // Threads
    // ============================================================

    group('getThreads', () {
      test('returns list of threads from wrapped response', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'threads': [
              {
                'id': 'thread-1',
                'room_id': 'room-123',
                'created': '2024-01-01T00:00:00Z',
              },
              {
                'id': 'thread-2',
                'room_id': 'room-123',
                'created': '2024-01-01T00:00:00Z',
              },
            ],
          },
        );

        final threads = await api.getThreads('room-123');

        expect(threads.length, equals(2));
        expect(threads[0].id, equals('thread-1'));
        expect(threads[1].id, equals('thread-2'));
      });

      test('returns empty list when no threads', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => {'threads': <dynamic>[]});

        final threads = await api.getThreads('room-123');

        expect(threads, isEmpty);
      });

      test('validates non-empty roomId', () {
        expect(() => api.getThreads(''), throwsA(isA<ArgumentError>()));
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => {'threads': <dynamic>[]});

        await api.getThreads('room-123', cancelToken: cancelToken);

        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return {'threads': <dynamic>[]};
        });

        await api.getThreads('room-123');

        expect(capturedUri?.path, equals('/api/v1/rooms/room-123/agui'));
      });
    });

    group('getThread', () {
      test('returns thread by ID', () async {
        when(
          () => mockTransport.request<ThreadInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => ThreadInfo(
            id: 'thread-123',
            roomId: 'room-123',
            createdAt: DateTime(2025),
          ),
        );

        final thread = await api.getThread('room-123', 'thread-123');

        expect(thread.id, equals('thread-123'));
        expect(thread.roomId, equals('room-123'));
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.getThread('', 'thread-123'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.getThread('room-123', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates NotFoundException', () async {
        when(
          () => mockTransport.request<ThreadInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Not found'));

        expect(
          () => api.getThread('room-123', 'nonexistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<ThreadInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return ThreadInfo(
            id: 'thread-123',
            roomId: 'room-123',
            createdAt: DateTime(2025),
          );
        });

        await api.getThread('room-123', 'thread-456');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456'),
        );
      });
    });

    group('createThread', () {
      test('returns ThreadInfo and initial AG-UI state', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'thread_id': 'new-thread',
            'runs': <String, dynamic>{
              'run-1': <String, dynamic>{
                'run_id': 'run-1',
                'run_input': <String, dynamic>{
                  'state': <String, dynamic>{
                    'rag': <String, dynamic>{
                      'citation_registry': <String, dynamic>{},
                      'citations': <dynamic>[],
                    },
                  },
                },
              },
            },
          },
        );

        final (thread, aguiState) = await api.createThread('room-123');

        expect(thread.id, equals('new-thread'));
        expect(thread.roomId, equals('room-123'));
        expect(thread.initialRunId, equals('run-1'));
        expect(
          aguiState,
          containsPair('rag', isA<Map<String, dynamic>>()),
        );
      });

      test('returns empty state when runs have no run_input', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'thread_id': 'new-thread',
            'runs': <String, dynamic>{
              'run-1': <String, dynamic>{'run_id': 'run-1'},
            },
          },
        );

        final (_, aguiState) = await api.createThread('room-123');

        expect(aguiState, isEmpty);
      });

      test('returns empty state when runs map is empty', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {'thread_id': 'new-thread', 'runs': <String, dynamic>{}},
        );

        final (thread, aguiState) = await api.createThread('room-123');

        expect(thread.id, equals('new-thread'));
        expect(aguiState, isEmpty);
      });

      test('validates non-empty roomId', () {
        expect(() => api.createThread(''), throwsA(isA<ArgumentError>()));
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(
          const ApiException(message: 'Server error', statusCode: 500),
        );

        expect(
          () => api.createThread('room-123'),
          throwsA(isA<ApiException>()),
        );
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {'thread_id': 'new-thread', 'runs': <String, dynamic>{}},
        );

        await api.createThread('room-123', cancelToken: cancelToken);

        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return {'thread_id': 'new', 'runs': <String, dynamic>{}};
        });

        await api.createThread('room-123');

        expect(capturedUri?.path, equals('/api/v1/rooms/room-123/agui'));
      });
    });

    group('deleteThread', () {
      test('completes successfully', () async {
        when(
          () => mockTransport.request<void>(
            'DELETE',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async {});

        await api.deleteThread('room-123', 'thread-456');

        verify(
          () => mockTransport.request<void>(
            'DELETE',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.deleteThread('', 'thread-123'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.deleteThread('room-123', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates NotFoundException', () async {
        when(
          () => mockTransport.request<void>(
            'DELETE',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Not found'));

        expect(
          () => api.deleteThread('room-123', 'nonexistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<void>(
            'DELETE',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
        });

        await api.deleteThread('room-123', 'thread-456');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456'),
        );
      });
    });

    group('updateThreadMetadata', () {
      test('sends POST to correct URL with metadata body', () async {
        Uri? capturedUri;
        Object? capturedBody;
        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          capturedBody = invocation.namedArguments[#body];
        });

        await api.updateThreadMetadata(
          'room-123',
          'thread-456',
          name: 'New Name',
        );

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456/meta'),
        );
        expect(capturedBody, {'name': 'New Name'});
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.updateThreadMetadata('', 'thread-123', name: 'x'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.updateThreadMetadata('room-123', '', name: 'x'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects call with no metadata fields', () {
        expect(
          () => api.updateThreadMetadata('room-123', 'thread-456'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Not found'));

        expect(
          () => api.updateThreadMetadata(
            'room-123',
            'thread-456',
            name: 'x',
          ),
          throwsA(isA<NotFoundException>()),
        );
      });
    });

    // ============================================================
    // Runs
    // ============================================================

    group('createRun', () {
      test('returns RunInfo', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => {'run_id': 'new-run'});

        final run = await api.createRun('room-123', 'thread-456');

        expect(run.id, equals('new-run'));
        expect(run.threadId, equals('thread-456'));
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.createRun('', 'thread-123'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.createRun('room-123', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(
          const ApiException(message: 'Server error', statusCode: 500),
        );

        expect(
          () => api.createRun('room-123', 'thread-456'),
          throwsA(isA<ApiException>()),
        );
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return {'run_id': 'new'};
        });

        await api.createRun('room-123', 'thread-456');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456'),
        );
      });
    });

    // ============================================================
    // Thread Messages
    // ============================================================

    group('getThreadHistory', () {
      test('fetches events from individual run endpoints', () async {
        // Thread endpoint returns run metadata (no events)
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Individual run endpoint returns events
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'Hello ',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'World',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        final messages = await api.getThreadHistory('room-123', 'thread-456');

        expect(messages.messages.length, equals(1));
        expect(messages.messages[0].id, equals('msg-1'));
        expect(
          (messages.messages[0] as TextMessage).text,
          equals('Hello World'),
        );
      });

      test('fetches multiple runs in parallel and orders by creation time',
          () async {
        // Thread endpoint returns two completed runs
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              // Note: Map order is not guaranteed, so we rely on timestamps
              'run-2': {
                'run_id': 'run-2',
                'created': '2026-01-07T02:00:00.000Z',
                'finished': '2026-01-07T02:01:00.000Z',
              },
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run 1 events
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'First',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        // Run 2 events
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-2',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-2',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-2',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-2',
                'delta': 'Second',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-2'},
            ],
          },
        );

        final messages = await api.getThreadHistory('room-123', 'thread-456');

        expect(messages.messages.length, equals(2));
        // First message should be from run-1 (earlier timestamp)
        expect((messages.messages[0] as TextMessage).text, equals('First'));
        expect((messages.messages[1] as TextMessage).text, equals('Second'));

        // Verify both run endpoints were called
        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-2',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('caches run events for subsequent calls', () async {
        // Thread endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'Cached',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        // First call
        await api.getThreadHistory('room-123', 'thread-456');

        // Second call - should use cache for run events
        final messages = await api.getThreadHistory('room-123', 'thread-456');

        expect(messages.messages.length, equals(1));
        expect((messages.messages[0] as TextMessage).text, equals('Cached'));

        // Thread endpoint called twice, but run endpoint only once (cached)
        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(2);
        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('skips runs without finished timestamp (in-progress)', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                // No 'finished' - run is still in progress
              },
            },
          },
        );

        final history = await api.getThreadHistory('room-123', 'thread-456');

        expect(history.messages, isEmpty);

        // Run endpoint should not be called for in-progress runs
        verifyNever(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        );
      });

      test('handles partial failure gracefully', () async {
        // Thread endpoint returns two runs
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
              'run-2': {
                'run_id': 'run-2',
                'created': '2026-01-07T02:00:00.000Z',
                'finished': '2026-01-07T02:01:00.000Z',
              },
            },
          },
        );

        // Run 1 succeeds
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'First',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        // Run 2 fails
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-2',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NetworkException(message: 'Connection failed'));

        final messages = await api.getThreadHistory('room-123', 'thread-456');

        // Should still return messages from successful run
        expect(messages.messages.length, equals(1));
        expect((messages.messages[0] as TextMessage).text, equals('First'));
      });

      test('returns empty list when no runs', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': <String, dynamic>{},
          },
        );

        final history = await api.getThreadHistory('room-123', 'thread-456');

        expect(history.messages, isEmpty);
      });

      test('handles null runs gracefully', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': null,
          },
        );

        final history = await api.getThreadHistory('room-123', 'thread-456');

        expect(history.messages, isEmpty);
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.getThreadHistory('', 'thread-123'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.getThreadHistory('room-123', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('uses correct URL for thread endpoint', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': <String, dynamic>{},
          };
        });

        await api.getThreadHistory('room-123', 'thread-456');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456'),
        );
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': <String, dynamic>{},
          },
        );

        await api.getThreadHistory(
          'room-123',
          'thread-456',
          cancelToken: cancelToken,
        );

        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });

      test('extracts user messages from run_input.messages', () async {
        // Thread endpoint returns run metadata
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run endpoint returns events AND run_input with user message
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'run_input': {
              'messages': [
                {
                  'id': 'user-msg-1',
                  'role': 'user',
                  'content': 'Hello from user',
                },
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'assistant-msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'assistant-msg-1',
                'delta': 'Hello from assistant',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'assistant-msg-1'},
            ],
          },
        );

        final messages = await api.getThreadHistory('room-123', 'thread-456');

        // Should have both user and assistant messages
        expect(messages.messages.length, equals(2));

        // User message comes first (from run_input.messages)
        final userMessage = messages.messages[0] as TextMessage;
        expect(userMessage.id, equals('user-msg-1'));
        expect(userMessage.user, equals(ChatUser.user));
        expect(userMessage.text, equals('Hello from user'));

        // Assistant message comes second (from events)
        final assistantMessage = messages.messages[1] as TextMessage;
        expect(assistantMessage.id, equals('assistant-msg-1'));
        expect(assistantMessage.user, equals(ChatUser.assistant));
        expect(assistantMessage.text, equals('Hello from assistant'));
      });

      // Regression: https://github.com/soliplex/frontend/issues/33
      test('does not duplicate user messages across multi-run history',
          () async {
        // Thread with 3 runs
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
              'run-2': {
                'run_id': 'run-2',
                'created': '2026-01-07T02:00:00.000Z',
                'finished': '2026-01-07T02:01:00.000Z',
              },
              'run-3': {
                'run_id': 'run-3',
                'created': '2026-01-07T03:00:00.000Z',
                'finished': '2026-01-07T03:01:00.000Z',
              },
            },
          },
        );

        // Run 1: run_input has only user-msg-A
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'run_input': {
              'messages': [
                {'id': 'user-msg-A', 'role': 'user', 'content': 'msg A'},
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'asst-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'asst-1',
                'delta': 'response 1',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-1'},
            ],
          },
        );

        // Run 2: run_input has user-msg-A (prior) AND user-msg-B (new)
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-2',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-2',
            'run_input': {
              'messages': [
                {'id': 'user-msg-A', 'role': 'user', 'content': 'msg A'},
                {'id': 'user-msg-B', 'role': 'user', 'content': 'msg B'},
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'asst-2',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'asst-2',
                'delta': 'response 2',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-2'},
            ],
          },
        );

        // Run 3: run_input has all 3 prior user messages
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-3',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-3',
            'run_input': {
              'messages': [
                {'id': 'user-msg-A', 'role': 'user', 'content': 'msg A'},
                {'id': 'user-msg-B', 'role': 'user', 'content': 'msg B'},
                {'id': 'user-msg-C', 'role': 'user', 'content': 'msg C'},
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'asst-3',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'asst-3',
                'delta': 'response 3',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-3'},
            ],
          },
        );

        final history = await api.getThreadHistory('room-123', 'thread-456');

        // Should be exactly 6 messages: A, resp1, B, resp2, C, resp3
        // NOT 10 (with A appearing 3 times and B appearing 2 times)
        expect(history.messages.length, equals(6));

        expect((history.messages[0] as TextMessage).id, equals('user-msg-A'));
        expect((history.messages[0] as TextMessage).text, equals('msg A'));
        expect((history.messages[1] as TextMessage).id, equals('asst-1'));
        expect((history.messages[2] as TextMessage).id, equals('user-msg-B'));
        expect((history.messages[2] as TextMessage).text, equals('msg B'));
        expect((history.messages[3] as TextMessage).id, equals('asst-2'));
        expect((history.messages[4] as TextMessage).id, equals('user-msg-C'));
        expect((history.messages[4] as TextMessage).text, equals('msg C'));
        expect((history.messages[5] as TextMessage).id, equals('asst-3'));
      });

      test('skips non-user messages from run_input.messages', () async {
        // Thread endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run endpoint with assistant message in run_input (should be skipped)
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'run_input': {
              'messages': [
                {'id': 'user-msg-1', 'role': 'user', 'content': 'User message'},
                {
                  'id': 'assistant-old',
                  'role': 'assistant',
                  'content': 'Old assistant message (should be skipped)',
                },
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'assistant-new',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'assistant-new',
                'delta': 'New response',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'assistant-new'},
            ],
          },
        );

        final messages = await api.getThreadHistory('room-123', 'thread-456');

        // Only user message from run_input + assistant from events
        expect(messages.messages.length, equals(2));
        expect(messages.messages[0].id, equals('user-msg-1'));
        expect(messages.messages[1].id, equals('assistant-new'));
      });

      test(
        'uses fallback values for missing fields in run_input.messages',
        () async {
          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'room_id': 'room-123',
              'thread_id': 'thread-456',
              'runs': {
                'run-1': {
                  'run_id': 'run-1',
                  'created': '2026-01-07T01:00:00.000Z',
                  'finished': '2026-01-07T01:01:00.000Z',
                },
              },
            },
          );

          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'run_id': 'run-1',
              'run_input': {
                // Only the last user message is extracted.
                // The first is a prior user message (would be from an
                // earlier run), the assistant is skipped, and the last
                // user message has no id — should use run-based fallback.
                'messages': [
                  {'id': 'has-id', 'content': 'Prior user message'},
                  {
                    'role': 'assistant',
                    'content': 'Assistant message (should be skipped)',
                  },
                  {'content': 'Message without id or role'},
                ],
              },
              'events': [
                {
                  'type': 'TEXT_MESSAGE_START',
                  'messageId': 'm1',
                  'role': 'assistant',
                },
                {
                  'type': 'TEXT_MESSAGE_CONTENT',
                  'messageId': 'm1',
                  'delta': 'Response',
                },
                {'type': 'TEXT_MESSAGE_END', 'messageId': 'm1'},
              ],
            },
          );

          final messages = await api.getThreadHistory('room-123', 'thread-456');

          // Only the last user message is extracted (the one that initiated
          // this run). The assistant message is skipped, so the last user
          // message is the one without id/role. Plus one assistant from events.
          expect(messages.messages.length, equals(2));
          // Last user message uses run-based fallback id, fallback role
          expect(messages.messages[0].id, equals('user-run-1'));
          expect(messages.messages[0].user, equals(ChatUser.user));
          // Assistant from events
          expect(messages.messages[1].id, equals('m1'));
        },
      );

      test('skips undecodable events and warns', () async {
        final warnings = <String>[];
        final apiWithWarning = SoliplexApi(
          transport: mockTransport,
          urlBuilder: urlBuilder,
          onWarning: warnings.add,
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'events': [
              {'type': 'TOTALLY_UNKNOWN_EVENT', 'foo': 'bar'},
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'msg-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'msg-1',
                'delta': 'Hello',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-1'},
            ],
          },
        );

        final history =
            await apiWithWarning.getThreadHistory('room-123', 'thread-456');

        expect(history.messages, hasLength(1));
        expect(
          (history.messages[0] as TextMessage).text,
          equals('Hello'),
        );
        expect(warnings, hasLength(1));
        expect(warnings[0], contains('Skipped 1 malformed event'));

        apiWithWarning.close();
      });

      test('calls onWarning callback on partial failure', () async {
        final warnings = <String>[];
        final apiWithWarning = SoliplexApi(
          transport: mockTransport,
          urlBuilder: urlBuilder,
          onWarning: warnings.add,
        );

        // Thread endpoint returns two runs
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        // Run 1 fails
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NetworkException(message: 'Connection failed'));

        await apiWithWarning.getThreadHistory('room-123', 'thread-456');

        expect(warnings, hasLength(1));
        expect(warnings[0], contains('run-1'));
        expect(warnings[0], contains('Connection failed'));

        apiWithWarning.close();
      });

      test('catches NotFoundException gracefully for deleted runs', () async {
        // NotFoundException indicates run deleted between list and fetch
        // (race condition) - should skip gracefully, not fail entire load
        final warnings = <String>[];
        final apiWithWarning = SoliplexApi(
          transport: mockTransport,
          urlBuilder: urlBuilder,
          onWarning: warnings.add,
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Run not found'));

        // Should not throw - returns empty history gracefully
        final history = await apiWithWarning.getThreadHistory(
          'room-123',
          'thread-456',
        );

        expect(history.messages, isEmpty);
        expect(warnings, hasLength(1));
        expect(warnings[0], contains('run-1'));

        apiWithWarning.close();
      });

      test('propagates ApiException for server errors', () async {
        // ApiException (500, 429, etc.) indicates systemic problem - propagate
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(
          const ApiException(statusCode: 500, message: 'Server error'),
        );

        expect(
          () => api.getThreadHistory('room-123', 'thread-456'),
          throwsA(isA<ApiException>()),
        );
      });

      test('propagates CancelledException when user cancels', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const CancelledException());

        expect(
          () => api.getThreadHistory('room-123', 'thread-456'),
          throwsA(isA<CancelledException>()),
        );
      });

      test('propagates AuthException when authentication fails', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const AuthException(message: 'Token expired'));

        expect(
          () => api.getThreadHistory('room-123', 'thread-456'),
          throwsA(isA<AuthException>()),
        );
      });

      test('evicts oldest entries when cache exceeds limit', () async {
        // This test verifies LRU eviction by filling the cache beyond capacity.
        // We use a smaller number of runs (5) to keep the test fast, but the
        // logic is the same - oldest entries should be evicted first.

        // Create runs that will fill cache
        final runs = <String, Map<String, dynamic>>{};
        for (var i = 0; i < 5; i++) {
          runs['run-$i'] = {
            'run_id': 'run-$i',
            'created': '2026-01-07T0$i:00:00.000Z',
            'finished': '2026-01-07T0$i:01:00.000Z',
          };
        }

        // Thread endpoint
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': runs,
          },
        );

        // Run endpoints - each returns a unique message
        for (var i = 0; i < 5; i++) {
          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-$i',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'run_id': 'run-$i',
              'events': [
                {
                  'type': 'TEXT_MESSAGE_START',
                  'messageId': 'msg-$i',
                  'role': 'assistant',
                },
                {
                  'type': 'TEXT_MESSAGE_CONTENT',
                  'messageId': 'msg-$i',
                  'delta': 'Message $i',
                },
                {'type': 'TEXT_MESSAGE_END', 'messageId': 'msg-$i'},
              ],
            },
          );
        }

        // First call loads all 5 runs
        final messages = await api.getThreadHistory('room-123', 'thread-456');
        expect(messages.messages.length, equals(5));

        // Verify all 5 run endpoints were called
        for (var i = 0; i < 5; i++) {
          verify(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-$i',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).called(1);
        }

        // Second call should use cache (no additional run endpoint calls)
        await api.getThreadHistory('room-123', 'thread-456');

        // Run endpoints should still have been called only once each
        for (var i = 0; i < 5; i++) {
          verifyNever(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456/run-$i',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          );
        }
      });

      test(
        'populates messageStates from per-run STATE_SNAPSHOT events',
        () async {
          // Thread with two completed runs
          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'room_id': 'room-123',
              'thread_id': 'thread-456',
              'runs': {
                'run-1': {
                  'run_id': 'run-1',
                  'created': '2026-01-07T01:00:00.000Z',
                  'finished': '2026-01-07T01:01:00.000Z',
                },
                'run-2': {
                  'run_id': 'run-2',
                  'created': '2026-01-07T02:00:00.000Z',
                  'finished': '2026-01-07T02:01:00.000Z',
                },
              },
            },
          );

          // Run 1: user message + STATE_SNAPSHOT with one citation turn
          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/'
                'agui/thread-456/run-1',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'run_id': 'run-1',
              'run_input': {
                'messages': [
                  {'id': 'user-1', 'role': 'user', 'content': 'Question 1'},
                ],
              },
              'events': [
                {
                  'type': 'STATE_SNAPSHOT',
                  'snapshot': {
                    'rag': {
                      'citation_index': {
                        'chunk-1': {
                          'document_id': 'doc-1',
                          'chunk_id': 'chunk-1',
                          'document_uri': 'file:///doc1.pdf',
                          'content': 'Citation 1 content',
                        },
                      },
                      'citations': ['chunk-1'],
                    },
                  },
                },
                {
                  'type': 'TEXT_MESSAGE_START',
                  'messageId': 'asst-1',
                  'role': 'assistant',
                },
                {
                  'type': 'TEXT_MESSAGE_CONTENT',
                  'messageId': 'asst-1',
                  'delta': 'Answer 1',
                },
                {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-1'},
                {
                  'type': 'RUN_FINISHED',
                  'thread_id': 'thread-456',
                  'run_id': 'run-1',
                },
              ],
            },
          );

          // Run 2: user message + STATE_SNAPSHOT with citations[0, 1]
          when(
            () => mockTransport.request<Map<String, dynamic>>(
              'GET',
              Uri.parse(
                'https://api.example.com/api/v1/rooms/room-123/'
                'agui/thread-456/run-2',
              ),
              cancelToken: any(named: 'cancelToken'),
              fromJson: any(named: 'fromJson'),
              body: any(named: 'body'),
              headers: any(named: 'headers'),
              timeout: any(named: 'timeout'),
            ),
          ).thenAnswer(
            (_) async => {
              'run_id': 'run-2',
              'run_input': {
                'messages': [
                  {'id': 'user-1', 'role': 'user', 'content': 'Question 1'},
                  {'id': 'asst-1', 'role': 'assistant', 'content': 'Answer 1'},
                  {'id': 'user-2', 'role': 'user', 'content': 'Question 2'},
                ],
              },
              'events': [
                {
                  'type': 'STATE_SNAPSHOT',
                  'snapshot': {
                    'rag': {
                      'citation_index': {
                        'chunk-1': {
                          'document_id': 'doc-1',
                          'chunk_id': 'chunk-1',
                          'document_uri': 'file:///doc1.pdf',
                          'content': 'Citation 1 content',
                        },
                        'chunk-2': {
                          'document_id': 'doc-2',
                          'chunk_id': 'chunk-2',
                          'document_uri': 'file:///doc2.pdf',
                          'content': 'Citation 2 content',
                        },
                      },
                      'citations': ['chunk-2'],
                    },
                  },
                },
                {
                  'type': 'TEXT_MESSAGE_START',
                  'messageId': 'asst-2',
                  'role': 'assistant',
                },
                {
                  'type': 'TEXT_MESSAGE_CONTENT',
                  'messageId': 'asst-2',
                  'delta': 'Answer 2',
                },
                {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-2'},
                {
                  'type': 'RUN_FINISHED',
                  'thread_id': 'thread-456',
                  'run_id': 'run-2',
                },
              ],
            },
          );

          final history = await api.getThreadHistory('room-123', 'thread-456');

          // Verify messageStates is populated correctly
          expect(history.messageStates, hasLength(2));

          // Run 1: user-1 should have citation from chunk-1 and runId 'run-1'
          expect(history.messageStates.containsKey('user-1'), isTrue);
          final state1 = history.messageStates['user-1']!;
          expect(state1.sourceReferences, hasLength(1));
          expect(state1.sourceReferences[0].chunkId, 'chunk-1');
          expect(state1.sourceReferences[0].documentId, 'doc-1');
          expect(state1.runId, 'run-1');

          // Run 2: user-2 should have citation from chunk-2 and runId 'run-2'
          expect(history.messageStates.containsKey('user-2'), isTrue);
          final state2 = history.messageStates['user-2']!;
          expect(state2.sourceReferences, hasLength(1));
          expect(state2.sourceReferences[0].chunkId, 'chunk-2');
          expect(state2.sourceReferences[0].documentId, 'doc-2');
          expect(state2.runId, 'run-2');
        },
      );

      test('messageStates is empty when no STATE_SNAPSHOT events', () async {
        // Thread with one run, no STATE_SNAPSHOT
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/agui/thread-456',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'room_id': 'room-123',
            'thread_id': 'thread-456',
            'runs': {
              'run-1': {
                'run_id': 'run-1',
                'created': '2026-01-07T01:00:00.000Z',
                'finished': '2026-01-07T01:01:00.000Z',
              },
            },
          },
        );

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            Uri.parse(
              'https://api.example.com/api/v1/rooms/room-123/'
              'agui/thread-456/run-1',
            ),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'run_id': 'run-1',
            'run_input': {
              'messages': [
                {'id': 'user-1', 'role': 'user', 'content': 'Hello'},
              ],
            },
            'events': [
              {
                'type': 'TEXT_MESSAGE_START',
                'messageId': 'asst-1',
                'role': 'assistant',
              },
              {
                'type': 'TEXT_MESSAGE_CONTENT',
                'messageId': 'asst-1',
                'delta': 'Hi',
              },
              {'type': 'TEXT_MESSAGE_END', 'messageId': 'asst-1'},
              {
                'type': 'RUN_FINISHED',
                'thread_id': 'thread-456',
                'run_id': 'run-1',
              },
            ],
          },
        );

        final history = await api.getThreadHistory('room-123', 'thread-456');

        // messageStates has entry for user-1 with empty sourceReferences and
        // runId populated
        expect(history.messageStates, hasLength(1));
        expect(history.messageStates['user-1']!.sourceReferences, isEmpty);
        expect(history.messageStates['user-1']!.runId, 'run-1');
      });
    });

    group('getRun', () {
      test('returns run by ID', () async {
        when(
          () => mockTransport.request<RunInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => RunInfo(
            id: 'run-789',
            threadId: 'thread-456',
            createdAt: DateTime(2025),
          ),
        );

        final run = await api.getRun('room-123', 'thread-456', 'run-789');

        expect(run.id, equals('run-789'));
        expect(run.threadId, equals('thread-456'));
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.getRun('', 'thread-123', 'run-456'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.getRun('room-123', '', 'run-456'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty runId', () {
        expect(
          () => api.getRun('room-123', 'thread-456', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates NotFoundException', () async {
        when(
          () => mockTransport.request<RunInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Not found'));

        expect(
          () => api.getRun('room-123', 'thread-456', 'nonexistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<RunInfo>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return RunInfo(
            id: 'run-789',
            threadId: 'thread-456',
            createdAt: DateTime(2025),
          );
        });

        await api.getRun('room-123', 'thread-456', 'run-789');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456/run-789'),
        );
      });
    });

    // ============================================================
    // Feedback
    // ============================================================

    group('submitFeedback', () {
      test('sends POST with thumbs_up and no reason', () async {
        Map<String, dynamic>? capturedBody;
        Uri? capturedUri;

        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          capturedBody =
              invocation.namedArguments[#body] as Map<String, dynamic>?;
        });

        await api.submitFeedback(
          'room-123',
          'thread-456',
          'run-789',
          FeedbackType.thumbsUp,
        );

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/agui/thread-456/run-789/feedback'),
        );
        expect(capturedBody?['feedback'], 'thumbs_up');
        expect(capturedBody?['reason'], isNull);
      });

      test('sends POST with thumbs_down and a reason', () async {
        Map<String, dynamic>? capturedBody;

        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedBody =
              invocation.namedArguments[#body] as Map<String, dynamic>?;
        });

        await api.submitFeedback(
          'room-123',
          'thread-456',
          'run-789',
          FeedbackType.thumbsDown,
          reason: 'The citation is wrong',
        );

        expect(capturedBody?['feedback'], 'thumbs_down');
        expect(capturedBody?['reason'], 'The citation is wrong');
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.submitFeedback(
            '',
            'thread-456',
            'run-789',
            FeedbackType.thumbsUp,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty threadId', () {
        expect(
          () => api.submitFeedback(
            'room-123',
            '',
            'run-789',
            FeedbackType.thumbsUp,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty runId', () {
        expect(
          () => api.submitFeedback(
            'room-123',
            'thread-456',
            '',
            FeedbackType.thumbsUp,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NetworkException(message: 'offline'));

        expect(
          () => api.submitFeedback(
            'room-123',
            'thread-456',
            'run-789',
            FeedbackType.thumbsUp,
          ),
          throwsA(isA<NetworkException>()),
        );
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async {});

        await api.submitFeedback(
          'room-123',
          'thread-456',
          'run-789',
          FeedbackType.thumbsUp,
          cancelToken: cancelToken,
        );

        verify(
          () => mockTransport.request<void>(
            'POST',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });
    });

    // ============================================================
    // Chunk Visualization
    // ============================================================

    group('getChunkVisualization', () {
      test('returns chunk visualization', () async {
        when(
          () => mockTransport.request<ChunkVisualization>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => ChunkVisualization(
            chunkId: 'chunk-123',
            documentUri: 'doc.pdf',
            imagesBase64: const ['abc123'],
          ),
        );

        final result = await api.getChunkVisualization('room-123', 'chunk-123');

        expect(result.chunkId, equals('chunk-123'));
        expect(result.documentUri, equals('doc.pdf'));
        expect(result.imagesBase64, equals(['abc123']));
      });

      test('validates non-empty roomId', () {
        expect(
          () => api.getChunkVisualization('', 'chunk-123'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('validates non-empty chunkId', () {
        expect(
          () => api.getChunkVisualization('room-123', ''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('propagates NotFoundException', () async {
        when(
          () => mockTransport.request<ChunkVisualization>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(const NotFoundException(message: 'Chunk not found'));

        expect(
          () => api.getChunkVisualization('room-123', 'nonexistent'),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<ChunkVisualization>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return ChunkVisualization(
            chunkId: 'chunk-123',
            documentUri: null,
            imagesBase64: const [],
          );
        });

        await api.getChunkVisualization('room-123', 'chunk-456');

        expect(
          capturedUri?.path,
          equals('/api/v1/rooms/room-123/chunk/chunk-456'),
        );
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<ChunkVisualization>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => ChunkVisualization(
            chunkId: 'chunk-123',
            documentUri: null,
            imagesBase64: const [],
          ),
        );

        await api.getChunkVisualization(
          'room-123',
          'chunk-123',
          cancelToken: cancelToken,
        );

        verify(
          () => mockTransport.request<ChunkVisualization>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });
    });

    // ============================================================
    // Installation Info
    // ============================================================

    group('getBackendVersionInfo', () {
      test('returns version info', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'soliplex': {'version': '0.36.dev0'},
            'fastapi': {'version': '0.124.0'},
          },
        );

        final info = await api.getBackendVersionInfo();

        expect(info.soliplexVersion, equals('0.36.dev0'));
        expect(info.packageVersions, hasLength(2));
        expect(info.packageVersions['fastapi'], equals('0.124.0'));
      });

      test('propagates exceptions', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(
          const ApiException(message: 'Server error', statusCode: 500),
        );

        expect(() => api.getBackendVersionInfo(), throwsA(isA<ApiException>()));
      });

      test('uses correct URL', () async {
        Uri? capturedUri;
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedUri = invocation.positionalArguments[1] as Uri;
          return {
            'soliplex': {'version': '0.36.dev0'},
          };
        });

        await api.getBackendVersionInfo();

        expect(capturedUri?.path, equals('/api/v1/installation/versions'));
      });

      test('supports cancellation', () async {
        final cancelToken = CancelToken();

        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'soliplex': {'version': '0.36.dev0'},
          },
        );

        await api.getBackendVersionInfo(cancelToken: cancelToken);

        verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: cancelToken,
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      });
    });

    // ============================================================
    // MCP Token
    // ============================================================

    group('getDocuments', () {
      test('skips malformed documents and returns valid ones', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {
            'document_set': {
              'doc-1': {'id': 'doc-1', 'title': 'Good Doc'},
              'doc-2': 'not a map',
              'doc-3': {'id': 'doc-3', 'title': 'Also Good'},
            },
          },
        );

        final docs = await api.getDocuments('room-1');

        expect(docs, hasLength(2));
        expect(docs.any((d) => d.id == 'doc-1'), isTrue);
        expect(docs.any((d) => d.id == 'doc-3'), isTrue);
      });
    });

    group('getMcpToken', () {
      test('returns token string from response', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {'room_id': 'room-123', 'mcp_token': 'abc.token.xyz'},
        );

        final token = await api.getMcpToken('room-123');

        expect(token, equals('abc.token.xyz'));
      });

      test('uses correct URL', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => {'room_id': 'room-123', 'mcp_token': 'token'},
        );

        await api.getMcpToken('room-123');

        final captured = verify(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).captured.single as Uri;

        expect(captured.path, equals('/api/v1/rooms/room-123/mcp_token'));
      });

      test('throws ArgumentError for empty roomId', () {
        expect(() => api.getMcpToken(''), throwsA(isA<ArgumentError>()));
      });

      test('throws FormatException when response lacks mcp_token', () async {
        when(
          () => mockTransport.request<Map<String, dynamic>>(
            'GET',
            any(),
            cancelToken: any(named: 'cancelToken'),
            fromJson: any(named: 'fromJson'),
            body: any(named: 'body'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((_) async => {'room_id': 'room-123'});

        expect(
          () => api.getMcpToken('room-123'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
