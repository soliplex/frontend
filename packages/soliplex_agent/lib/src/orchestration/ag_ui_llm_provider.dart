import 'dart:async';

import 'package:async/async.dart';
import 'package:soliplex_agent/src/models/thread_key.dart';
import 'package:soliplex_agent/src/orchestration/agent_llm_provider.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_agent.ag_ui_llm_provider');

/// AG-UI backend adapter implementing [AgentLlmProvider].
///
/// Wraps [SoliplexApi] (run creation) and [AgUiStreamClient] (SSE streaming)
/// into the [AgentLlmProvider] contract.
class AgUiLlmProvider implements AgentLlmProvider {
  /// Creates an [AgUiLlmProvider] from existing AG-UI clients.
  const AgUiLlmProvider({
    required SoliplexApi api,
    required AgUiStreamClient agUiStreamClient,
  })  : _api = api,
        _agUiStreamClient = agUiStreamClient;

  final SoliplexApi _api;
  final AgUiStreamClient _agUiStreamClient;

  /// With [existingRunId], waits for the backend's first answer on that run
  /// before returning, so a refusal, which proves this send did not start
  /// the run, throws here, before the run is handed on. When the refusal is
  /// a 400 and the thread, read again, no longer shows [existingRunId] as its
  /// unused initial run, the run is taken as started first, by another client
  /// or by a send whose answer was lost: the message is sent instead on a
  /// run created for it.
  @override
  Future<LlmRunHandle> startRun({
    required ThreadKey key,
    required SimpleRunAgentInput input,
    String? existingRunId,
    String? parentRunId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) async {
    LlmRunHandle runOn(String runId) => LlmRunHandle(
          runId: runId,
          events: _agUiStreamClient.runAgent(
            _endpoint(key, runId),
            SimpleRunAgentInput(
              threadId: input.threadId,
              runId: runId,
              messages: input.messages,
              tools: input.tools,
              state: input.state,
              forwardedProps: input.forwardedProps,
            ),
            cancelToken: cancelToken,
            onReconnectStatus: onReconnectStatus,
          ),
        );

    if (existingRunId == null) {
      return runOn(await _createRun(key, parentRunId));
    }
    try {
      final events = await _answered(runOn(existingRunId).events);
      return LlmRunHandle(runId: existingRunId, events: events);
    } on ApiException catch (error, stackTrace) {
      if (error.statusCode != 400 ||
          !await _startedElsewhere(key, existingRunId, cancelToken)) {
        rethrow;
      }
      _logger.warning(
        "The thread's initial run was already started; a run is being "
        'created for the message.',
        error: error,
        stackTrace: stackTrace,
        attributes: {
          'roomId': key.roomId,
          'threadId': key.threadId,
          'refusedRunId': existingRunId,
        },
      );
      return runOn(await _createRun(key, parentRunId));
    }
  }

  /// [events] once the backend has answered: its first outcome has arrived,
  /// or the stream ended without one.
  ///
  /// Throws the first error only when it is a refusal. Any other error before
  /// an answer, such as a dropped connection or a cancel, stays in the
  /// returned stream: the backend may have started the run before it, so the
  /// run is ended as one that was sent, keeping the message in the
  /// conversation. That includes a cancel that came before the request was
  /// sent (while it waited for a free connection or a token), which the
  /// client reports no differently.
  static Future<Stream<DecodeOutcome>> _answered(
    Stream<DecodeOutcome> events,
  ) async {
    final queue = StreamQueue(events);
    try {
      if (await queue.hasNext) await queue.peek;
    } on Object catch (error, stackTrace) {
      unawaited(queue.cancel());
      if (_isRefusal(error)) rethrow;
      return Stream.error(error, stackTrace);
    }
    return queue.rest;
  }

  /// Whether [error] proves this send did not start the run: the backend
  /// answered with a 4xx status, which it sends only before storing the
  /// run's input.
  static bool _isRefusal(Object error) => switch (error) {
        AuthException() ||
        PermissionDeniedException() ||
        NotFoundException() =>
          true,
        ApiException(:final statusCode) =>
          statusCode >= 400 && statusCode < 500,
        _ => false,
      };

  /// Whether [runId] is no longer the thread's unused initial run, as the
  /// backend reports the thread now. False when the thread cannot be read,
  /// so the refusal is reported as it came; a cancel is rethrown.
  Future<bool> _startedElsewhere(
    ThreadKey key,
    String runId,
    CancelToken? cancelToken,
  ) async {
    final ThreadHistory history;
    try {
      history = await _api.getThreadHistory(
        key.roomId,
        key.threadId,
        cancelToken: cancelToken,
      );
    } on CancelledException {
      rethrow;
    } on Object catch (error, stackTrace) {
      // A SoliplexException's message names statuses, hosts, paths, keys,
      // type names and the server's written reason, none of them a
      // credential, so it is kept. Anything else may echo what users wrote
      // in the runs, so it is reduced to its shape.
      final requestFailed = error is SoliplexException;
      _logger.warning(
        'Could not re-read the thread to tell whether its refused initial run '
        'was started; the refusal is reported as it came.',
        error: requestFailed ? error : null,
        attributes: {
          'roomId': key.roomId,
          'threadId': key.threadId,
          'runId': runId,
          if (!requestFailed) 'failure': describeFailure(error),
        },
        stackTrace: stackTrace,
      );
      return false;
    }
    return history.unusedInitialRunId != runId;
  }

  @override
  LlmRunHandle followRun({
    required ThreadKey key,
    required String runId,
    CancelToken? cancelToken,
    void Function(ReconnectStatus)? onReconnectStatus,
  }) {
    final events = _agUiStreamClient.followRun(
      _endpoint(key, runId),
      runId,
      cancelToken: cancelToken,
      onReconnectStatus: onReconnectStatus,
    );
    return LlmRunHandle(runId: runId, events: events);
  }

  String _endpoint(ThreadKey key, String runId) =>
      'rooms/${key.roomId}/agui/${key.threadId}/$runId';

  Future<String> _createRun(ThreadKey key, String? parentRunId) async {
    final runInfo = await _api.createRun(
      key.roomId,
      key.threadId,
      parentRunId: parentRunId,
    );
    return runInfo.id;
  }
}
