import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/src/orchestration/ag_ui_llm_provider.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

void main() {
  late MockSoliplexApi mockApi;
  late MockAgUiStreamClient mockStreamClient;
  late AgUiLlmProvider provider;

  const key = (
    serverId: 'server-1',
    roomId: 'room-1',
    threadId: 'thread-1',
  );

  setUpAll(() {
    registerFallbackValue(
      const SimpleRunAgentInput(threadId: 'fallback', runId: 'fallback'),
    );
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    mockApi = MockSoliplexApi();
    mockStreamClient = MockAgUiStreamClient();
    provider = AgUiLlmProvider(
      api: mockApi,
      agUiStreamClient: mockStreamClient,
    );
  });

  tearDown(() {
    reset(mockApi);
    reset(mockStreamClient);
  });

  group('AgUiLlmProvider', () {
    group('startRun', () {
      test('creates run via API when existingRunId is null', () async {
        when(
          () => mockApi.createRun('room-1', 'thread-1'),
        ).thenAnswer(
          (_) async => RunInfo(
            id: 'new-run-id',
            threadId: 'thread-1',
            createdAt: DateTime(2026),
          ),
        );
        when(
          () => mockStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => const Stream.empty());

        final handle = await provider.startRun(
          key: key,
          input: const SimpleRunAgentInput(
            threadId: 'thread-1',
            runId: 'placeholder',
          ),
        );

        expect(handle.runId, 'new-run-id');
        verify(() => mockApi.createRun('room-1', 'thread-1')).called(1);
      });

      test('reuses existingRunId without calling API', () async {
        when(
          () => mockStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => const Stream.empty());

        final handle = await provider.startRun(
          key: key,
          input: const SimpleRunAgentInput(
            threadId: 'thread-1',
            runId: 'placeholder',
          ),
          existingRunId: 'existing-run-42',
        );

        expect(handle.runId, 'existing-run-42');
        verifyNever(() => mockApi.createRun(any(), any()));
      });

      test('builds correct endpoint from key and runId', () async {
        when(
          () => mockStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => const Stream.empty());

        await provider.startRun(
          key: key,
          input: const SimpleRunAgentInput(
            threadId: 'thread-1',
            runId: 'placeholder',
          ),
          existingRunId: 'run-99',
        );

        verify(
          () => mockStreamClient.runAgent(
            'rooms/room-1/agui/thread-1/run-99',
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).called(1);
      });

      test('passes resolved runId in input to stream client', () async {
        when(
          () => mockStreamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).thenAnswer((_) => const Stream.empty());

        await provider.startRun(
          key: key,
          input: const SimpleRunAgentInput(
            threadId: 'thread-1',
            runId: 'will-be-replaced',
            messages: [],
          ),
          existingRunId: 'correct-run-id',
        );

        final captured = verify(
          () => mockStreamClient.runAgent(
            any(),
            captureAny(),
            cancelToken: any(named: 'cancelToken'),
            resumePolicy: any(named: 'resumePolicy'),
            onReconnectStatus: any(named: 'onReconnectStatus'),
          ),
        ).captured;

        final input = captured.single as SimpleRunAgentInput;
        expect(input.runId, 'correct-run-id');
        expect(input.threadId, 'thread-1');
      });
    });
  });
}
