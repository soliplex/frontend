@Tags(['integration'])
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        DartHttpClient,
        HttpErrorEvent,
        HttpObserver,
        HttpRequestEvent,
        HttpResponseEvent,
        HttpStreamEndEvent,
        HttpStreamStartEvent,
        ObservableHttpClient;
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

import 'helpers/integration_harness.dart';

/// Verbose AG-UI integration test via AgentRuntime.
///
/// Instruments HTTP traffic through the full AgentRuntime → RunOrchestrator
/// → AG-UI SSE path. Uses ObservableHttpClient to log all requests.
///
/// Run individual rooms to avoid demo backend rate limits:
/// ```bash
/// SOLIPLEX_BASE_URL=https://demo.toughserv.com \
///   dart test test/integration/verbose_agui_test.dart \
///   -t integration --name "soliplex"
/// ```
///
/// Available room tests: soliplex, cooking, travel.
void main() {
  late AgentRuntime runtime;

  final httpLog = <String>[];

  setUpAll(() {
    final baseUrl = env('SOLIPLEX_BASE_URL', 'https://demo.toughserv.com');
    final observer = _TestHttpObserver(httpLog);

    final httpClient = ObservableHttpClient(
      client: DartHttpClient(),
      observers: [observer],
    );

    final logManager =
        LogManager.instance
          ..minimumLevel = LogLevel.debug
          ..addSink(StdoutSink());

    final connection = ServerConnection.create(
      serverId: 'default',
      serverUrl: baseUrl,
      httpClient: httpClient,
    );
    runtime = AgentRuntime(
      connection: connection,
      llmProvider: AgUiLlmProvider(
        api: connection.api,
        agUiStreamClient: connection.agUiStreamClient,
      ),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      platform: const NativePlatformConstraints(),
      logger: logManager.getLogger('verbose'),
    );
  });

  tearDownAll(() async {
    await runtime.dispose();
  });

  for (final spec in _roomSpecs) {
    test('spawn round-trip in ${spec.roomId} room', () async {
      httpLog.clear();

      stderr
        ..writeln('=== ${spec.roomId} room ===')
        ..writeln('prompt: ${spec.prompt}');

      final session = await runtime.spawn(
        roomId: spec.roomId,
        prompt: spec.prompt,
      );

      stderr.writeln('threadId: ${session.threadKey.threadId}');

      final result = await session.awaitResult(
        timeout: const Duration(seconds: 60),
      );

      stderr.writeln('--- result: ${result.runtimeType} ---');
      switch (result) {
        case AgentSuccess(:final output):
          stderr.writeln(
            'output (${output.length} chars): '
            '${output.substring(0, output.length.clamp(0, 300))}',
          );
        case AgentFailure(:final reason, :final error):
          stderr.writeln('FAILED: $reason — $error');
        case AgentTimedOut(:final elapsed):
          stderr.writeln('TIMED OUT after $elapsed');
      }

      _dump('HTTP events', httpLog);

      expect(result, isA<AgentSuccess>(), reason: spec.roomId);
      if (result is AgentSuccess) {
        expect(
          result.output,
          isNotEmpty,
          reason: 'Expected non-empty output from ${spec.roomId}',
        );
      }
    });
  }
}

const _roomSpecs = [
  _RoomSpec('soliplex', 'Say hello in one sentence.'),
  _RoomSpec('cooking', 'What is a good recipe for scrambled eggs?'),
  _RoomSpec('travel', 'What should I see in Paris?'),
];

class _RoomSpec {
  const _RoomSpec(this.roomId, this.prompt);
  final String roomId;
  final String prompt;
}

void _dump(String label, List<String> lines) {
  stderr.writeln('--- $label ---');
  lines.forEach(stderr.writeln);
}

class _TestHttpObserver implements HttpObserver {
  _TestHttpObserver(this._log);

  final List<String> _log;

  @override
  void onRequest(HttpRequestEvent event) {
    final body = event.body;
    final bodySnippet = body != null ? ' body=$body' : '';
    _log.add('[HTTP] ${event.method} ${event.uri}$bodySnippet');
  }

  @override
  void onResponse(HttpResponseEvent event) {
    final body = event.body;
    final bodySnippet = body != null ? ' body=$body' : '';
    _log.add(
      '[HTTP] ${event.statusCode} '
      '(${event.duration.inMilliseconds}ms, ${event.bodySize}B)$bodySnippet',
    );
  }

  @override
  void onError(HttpErrorEvent event) {
    _log.add('[HTTP] ERROR ${event.method} ${event.uri} ${event.exception}');
  }

  @override
  void onStreamStart(HttpStreamStartEvent event) {
    final body = event.body;
    final bodySnippet = body != null ? ' body=$body' : '';
    _log.add('[SSE] ${event.method} ${event.uri}$bodySnippet');
  }

  @override
  void onStreamEnd(HttpStreamEndEvent event) {
    final status = event.isSuccess ? 'OK' : 'ERROR';
    final body = event.body;
    final bodySnippet = body != null ? '\n  stream-body=$body' : '';
    _log.add(
      '[SSE] END $status (${event.duration.inMilliseconds}ms, '
      '${event.bytesReceived}B)$bodySnippet',
    );
  }
}
