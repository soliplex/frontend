import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart' show batch;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/util/debouncer.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.context_usage_controller');

/// Holds the context reading for one thread.
///
/// The reading predicts the thread's next request, and that request is the
/// thread's transcript: the history the next send carries. So the reading is
/// derived from the transcript rather than kept beside it.
///
/// - The measurement is the provider's own count for the last request of
///   the newest measured run, plus its reply. It covers the transcript up
///   to where that run ended. The backend is the only vantage point that
///   sees the whole request — instructions, tool and MCP schemas, the chat
///   template, evidence compaction — so nothing here recounts that part.
/// - What the transcript holds after the measured run is estimated: a run
///   that recorded no count, what an errored run streamed, a stopped
///   message. So is a send no transcript carries yet, and the draft.
///
/// Estimates are biased high on purpose; see [estimateDraftTokens]. Until
/// a run has measured something the reading offers no total at all — an
/// estimate is a fragment of a conversation nobody has counted.
///
/// Each thread view owns its controller, and selecting a thread creates a
/// new view, so leaving a thread clears a dismissed warning.
class ContextUsageController {
  /// Creates a controller for [threadId] in [roomId].
  ContextUsageController({
    required SoliplexApi api,
    required String roomId,
    required String threadId,
    required ReadonlySignal<int?> contextWindow,
    Duration draftDebounce = const Duration(milliseconds: 300),
  })  : _api = api,
        _roomId = roomId,
        _threadId = threadId,
        _contextWindow = contextWindow,
        _draftDebounce = Debouncer(draftDebounce);

  final SoliplexApi _api;
  final String _roomId;
  final String _threadId;
  final ReadonlySignal<int?> _contextWindow;
  final Debouncer _draftDebounce;

  final Signal<Transcript> _transcript = Signal<Transcript>(const Transcript());
  final Signal<MeasuredRun?> _measured = Signal<MeasuredRun?>(null);
  final Signal<int> _sendingTokens = Signal<int>(0);
  final Signal<int> _draftTokens = Signal<int>(0);
  final Signal<ContextLevel> _acknowledged =
      Signal<ContextLevel>(ContextLevel.room);
  bool _disposed = false;

  /// Tokens of the transcript the measurement does not cover. Apart from
  /// [usage] so that a keystroke does not re-estimate the transcript.
  late final ReadonlySignal<int> _unmeasuredTokens = computed(() {
    final messages = _transcript.value.messages;
    final covered = _measured.value?.coveredMessages ?? messages.length;
    if (covered >= messages.length) return 0;
    return estimateTranscriptTokens(messages.skip(covered));
  });

  /// The current reading.
  late final ReadonlySignal<ContextUsage> usage = computed(
    () => ContextUsage(
      measuredTokens: _measured.value?.usage.contextTokens,
      estimatedTokens: _unmeasuredTokens.value + _sendingTokens.value,
      draftTokens: _draftTokens.value,
      contextWindow: _contextWindow.value,
    ),
  );

  /// The reading while its level is above the level acknowledged; null
  /// otherwise. Dismissing acknowledges the current level and a send
  /// clears it.
  ///
  /// With nothing dismissed that is any level above
  /// [ContextLevel.room]. A dismissed warning returns when the reading
  /// reaches a worse level, or after the next send; a reading that falls
  /// back and climbs to the dismissed level again stays hidden.
  late final ReadonlySignal<ContextUsage?> warning = computed(() {
    final current = usage.value;
    return current.level.isWorseThan(_acknowledged.value) ? current : null;
  });

  /// Hides the warning until the reading reaches a worse level than it has
  /// now, or the next send starts.
  void dismissWarning() {
    if (_disposed) return;
    _acknowledged.value = usage.value.level;
  }

  /// Takes the transcript and measurement of a freshly loaded [history].
  ///
  /// The history is what the next send carries — it seeds the runtime — so
  /// its transcript is taken unless the one held is longer, and its
  /// measurement unless the one held covers more. Of every transcript the
  /// reading receives, only this one can arrive out of order: it is fetched
  /// when the thread opens and may land after a send, missing what the send
  /// added.
  void historyLoaded(ThreadHistory history) {
    if (_disposed) return;
    final latest = history.latestMeasurement;
    if (latest == null || latest.usage.contextTokens == null) {
      // Without this the gauge is hollow and says nothing about why: no
      // run in the thread has reported what its request cost.
      _logger.info(
        'Thread history carried no measurement',
        attributes: {
          'threadId': _threadId,
          'contextWindow': _contextWindow.value,
        },
      );
    }
    batch(() {
      if (history.transcript.messages.length >=
          _transcript.value.messages.length) {
        _transcript.value = history.transcript;
      }
      _adopt(latest);
    });
  }

  /// Counts [prompt], just sent, until a transcript carrying it arrives or
  /// the send ends, and clears a dismissed warning: whatever level the
  /// reading is at after the send shows again.
  void sendStarted(List<MessagePart> prompt) {
    if (_disposed) return;
    final text = [
      for (final part in prompt)
        if (part is TextPart) part.text,
    ].join('\n');
    batch(() {
      _acknowledged.value = ContextLevel.room;
      _sendingTokens.value = estimateDraftTokens(
        text,
        images: prompt.whereType<ImagePart>().length,
      );
    });
  }

  /// Takes the [transcript] of a run in progress.
  ///
  /// Called on every running state. A transcript holding as many
  /// messages as the one held is ignored: streamed text replaces a message
  /// in place, and re-estimating it per token buys nothing the run's end
  /// does not settle. The prompt, then each tool call and result, add
  /// messages, so the reading grows with the run's own requests — which is
  /// where a window overflows.
  void runProgressed(Transcript transcript) {
    if (_disposed) return;
    if (transcript.messages.length == _transcript.value.messages.length) {
      return;
    }
    batch(() {
      _sendingTokens.value = 0;
      _transcript.value = transcript;
    });
  }

  /// Takes the [transcript] [runId] completed with, then reads the run's
  /// count, which covers that transcript whole.
  ///
  /// Without a count — no record, or a failed fetch — what the run added
  /// stays estimated. Failure is quiet by design: the gauge keeps its last
  /// honest reading rather than interrupt the conversation.
  Future<void> runCompleted(String runId, Transcript transcript) async {
    if (_disposed) return;
    batch(() {
      _sendingTokens.value = 0;
      _transcript.value = transcript;
    });
    final RunUsage? found;
    try {
      found = await _api.getRunUsage(_roomId, _threadId, runId);
    } on Object catch (e, stackTrace) {
      // Catches an Error as well as an Exception: this is started with
      // `unawaited`, so whatever escapes has no caller to reach, only the
      // zone's handler. A network failure travels whole, because it renders
      // as the host and the OS error and that is the diagnosis. Anything
      // else can carry the value it failed on, so it is described instead;
      // an ApiException's message and body are the server's text, so only
      // its status code goes beside the description.
      _logger.warning(
        'Run usage fetch failed; the run stays estimated',
        error: e is NetworkException ? e : null,
        stackTrace: stackTrace,
        attributes: {
          'threadId': _threadId,
          'runId': runId,
          if (e is! NetworkException) 'failure': describeFailure(e),
          if (e is ApiException) 'statusCode': e.statusCode,
        },
      );
      // Logged whether or not the thread was left meanwhile; nothing is
      // written to the readings either way.
      return;
    }
    if (_disposed) return;

    if (found == null || found.contextTokens == null) {
      // `hasRecord` separates the causes: no record is a run that errored
      // before its first request, while a record without a count is a run
      // the model never answered — or a body that is not the backend's
      // record at all.
      _logger.info(
        'Run reported no measurement; the run stays estimated',
        attributes: {
          'threadId': _threadId,
          'runId': runId,
          'hasRecord': found != null,
        },
      );
      return;
    }

    _adopt(
      MeasuredRun(usage: found, coveredMessages: transcript.messages.length),
    );
  }

  /// Takes the [transcript] of a send that ended with no count to read.
  ///
  /// An errored run's transcript keeps what it streamed, a cut-off run's
  /// keeps its message, and both are carried into the next request, so both
  /// stay estimated. A cut-off run's count is not read even if the backend
  /// later records one: the backend finishes the run and counts more than
  /// this transcript kept. A send that never reached a run passes null and
  /// leaves nothing behind.
  void sendEnded(Transcript? transcript) {
    if (_disposed) return;
    batch(() {
      _sendingTokens.value = 0;
      if (transcript != null) _transcript.value = transcript;
    });
  }

  /// Records what is currently in the composer.
  ///
  /// Debounced while the composer holds text or images: the draft is the only
  /// term that moves while someone types. An empty composer applies at once
  /// and cancels any pending estimate — a send clears the composer, and an
  /// estimate landing after that would count the sent message a second time.
  void draftChanged(String draft, {int images = 0}) {
    if (_disposed) return;
    if (draft.isEmpty && images == 0) {
      _draftDebounce.cancel();
      _draftTokens.value = 0;
      return;
    }
    _draftDebounce.run(() {
      if (_disposed) return;
      _draftTokens.value = estimateDraftTokens(draft, images: images);
    });
  }

  /// Adopts [measured] unless the one held covers more of the transcript,
  /// which makes it the newer count.
  void _adopt(MeasuredRun? measured) {
    if (measured == null || measured.usage.contextTokens == null) return;
    final held = _measured.value;
    if (held == measured) return;
    if (held != null && held.coveredMessages > measured.coveredMessages) {
      return;
    }
    _measured.value = measured;
    if (measured.usage.finalOutputTokens == null) {
      // A backend that predates the field, or a run recorded before it
      // upgraded, leaves the reading one reply short while it shows as exact.
      _logger.warning(
        'Measured run has no reply count; the reading omits the last reply',
        attributes: {
          'threadId': _threadId,
          'runId': measured.usage.runId,
        },
      );
    }
    // The window is here because a null one is why an otherwise measured
    // thread shows no percentage.
    _logger.info(
      'Context reading measured',
      attributes: {
        'threadId': _threadId,
        'runId': measured.usage.runId,
        'finalInputTokens': measured.usage.finalInputTokens,
        'finalOutputTokens': measured.usage.finalOutputTokens,
        'coveredMessages': measured.coveredMessages,
        'contextWindow': _contextWindow.value,
      },
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _draftDebounce.cancel();
    warning.dispose();
    usage.dispose();
    _unmeasuredTokens.dispose();
    _transcript.dispose();
    _measured.dispose();
    _sendingTokens.dispose();
    _draftTokens.dispose();
    _acknowledged.dispose();
  }
}
