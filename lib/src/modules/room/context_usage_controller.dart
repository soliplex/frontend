import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/util/debouncer.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.context_usage_controller');

/// Holds the context reading for one thread.
///
/// Two numbers, from two places, neither computed here:
///
/// - The window is the room's, and arrives with the room, so it is
///   handed in rather than fetched.
/// - The measurement is the provider's own count for the last request of
///   the newest measured run, plus its reply, which the next request will
///   carry. It arrives with the thread's history, and after each run from
///   that run's usage record. The backend is the only
///   vantage point that sees the whole request — instructions, tool and
///   MCP schemas, the chat template, images, evidence compaction — so
///   reconstructing it here would necessarily read low.
///
/// What this adds locally is the estimate: the draft in the composer, and
/// a message already sent that no run has reported on yet. Both are biased
/// high on purpose; see [estimateDraftTokens]. Until a run has measured
/// something the reading offers no total at all — an estimate is a
/// fragment of a conversation nobody has counted, not a reading of it.
class ContextUsageController extends ChangeNotifier {
  /// Creates a controller for [threadId] in [roomId].
  ContextUsageController({
    required SoliplexApi api,
    required String roomId,
    required String threadId,
    this.contextWindow,
    Duration draftDebounce = const Duration(milliseconds: 300),
  })  : _api = api,
        _roomId = roomId,
        _threadId = threadId,
        _draftDebounce = Debouncer(draftDebounce);

  final SoliplexApi _api;
  final String _roomId;
  final String _threadId;
  final Debouncer _draftDebounce;

  /// The room's model's window, or null when nothing knows it — in which
  /// case the reading carries no percentage and the gauge shows a hollow
  /// ring rather than render against an invented denominator.
  ///
  /// Settable because the room loads on its own schedule and may arrive
  /// after this controller exists. Setting it does not notify: it is
  /// assigned from a build that reads [usage] straight after, and a
  /// notification there would be a rebuild inside a build.
  int? contextWindow;

  RunUsage? _measured;
  int _draftTokens = 0;
  int _inFlightTokens = 0;
  bool _disposed = false;

  /// How many measurements have been asked for, which is the only order
  /// available: a usage record carries no time of its own, and runs end
  /// in the order this is called.
  int _fetches = 0;

  /// The current reading.
  ///
  /// The terms go in apart: what the backend counted, and what is
  /// guessed here. What may be shown of them, and whether a percentage
  /// exists at all, is the reading's own to work out.
  ContextUsage get usage => ContextUsage(
        measuredTokens: _measured?.contextTokens,
        estimatedTokens: _draftTokens + _inFlightTokens,
        contextWindow: contextWindow,
      );

  /// The newest measured run's usage, or null before any run has been.
  RunUsage? get measured => _measured;

  /// Takes the measurement from a freshly loaded [history].
  ///
  /// Called when the thread's history loads. The history already carries
  /// the newest measured run, so this costs no request.
  ///
  /// A seed, not a correction: the fetch behind it was issued before any
  /// run this controller watched, so a measurement already in hand is at
  /// least as new and the history has nothing to add. A history carrying
  /// no measurement leaves the reading where it was.
  void historyLoaded(ThreadHistory history) {
    if (_disposed || _measured != null) return;

    final latest = history.latestUsage;
    if (latest == null || !latest.isMeasured) {
      // Without this the gauge is hollow and says nothing about why: no
      // run in the thread has reported what its request cost.
      _logger.info(
        'Thread history carried no measurement',
        attributes: {'threadId': _threadId, 'contextWindow': contextWindow},
      );
    }

    // Releases nothing: a seed says which run was measured, not which
    // messages an estimate here stands for. The run's own answer is what
    // releases it -- including when the seed named that same run.
    _measure(latest, releasing: 0);
  }

  /// Re-reads the measurement once [runId] has ended.
  ///
  /// The history is not re-read after a run, so the run's own usage is
  /// fetched. Failure is quiet by design: a context indicator that cannot
  /// refresh should keep showing its last honest reading, not interrupt
  /// the conversation. It keeps the in-flight estimate too — the message
  /// did reach the model, so dropping the term standing in for it would
  /// move the reading down after a send. A later run's measurement
  /// supersedes it. So does a run the backend has no count for, which
  /// can mean it never reached the model or that its provider reported
  /// no prompt tokens for the request it made. The previous reading
  /// stands either way.
  Future<void> runEnded(String runId) async {
    final fetch = ++_fetches;
    // What this answer can speak for: the run had started, so the model
    // saw everything held now. Anything banked while the request is open
    // is a later message it never saw.
    final heldAtRequest = _inFlightTokens;
    final RunUsage? found;

    try {
      found = await _api.getRunUsage(_roomId, _threadId, runId);
    } on Object catch (e, stackTrace) {
      // Catches an Error as well as an Exception: this is started with
      // `unawaited`, so whatever escapes has no caller to reach, only
      // the zone's handler.
      //
      // A network failure travels whole, because it renders as the host
      // and the OS error and that is the diagnosis. Anything else can
      // carry the value it failed on, so it is described instead.
      _logger.warning(
        'Run usage fetch failed; keeping the previous reading',
        error: e is NetworkException ? e : null,
        stackTrace: stackTrace,
        attributes: {
          'runId': runId,
          if (e is! NetworkException) 'failure': describeFailure(e),
        },
      );
      return;
    }

    // A later run ended while this was in flight, so this answer is about
    // a request the model has since moved past.
    if (_disposed || fetch != _fetches) return;

    if (found == null || !found.isMeasured) {
      // The reading goes stale here without changing, which looks from
      // the outside exactly like a reading that was already current.
      // `hasRecord` separates the causes: no record is the backend
      // saying the run produced no usage, while a record without a count
      // can be a run the model did see whose provider reported no prompt
      // tokens.
      _logger.info(
        'Run reported no measurement; the previous reading stands',
        attributes: {
          'threadId': _threadId,
          'runId': runId,
          'hasRecord': found != null,
        },
      );
    }

    _measure(found, releasing: heldAtRequest);
  }

  /// Records that a send ended with no run to report on it.
  ///
  /// Nothing will ever measure the message, so the estimate standing in
  /// for it has to come back out — and where the composer puts the text
  /// back, before the same message is counted again as a draft.
  void sendFailed() => _releaseEstimate(_inFlightTokens);

  /// Adopts [found], dropping the [releasing] tokens of estimate it
  /// accounts for and leaving any banked since it was asked for.
  void _measure(RunUsage? found, {required int releasing}) {
    // A run that measured nothing releases the estimate standing in for
    // the sent message: it either never reached the model or is already
    // inside the previous reading, and holding an estimate against a run
    // that has ended would read high for good.
    if (found == null || !found.isMeasured) {
      _releaseEstimate(releasing);
      return;
    }

    // Already the reading, so the number does not move -- but the answer
    // still covers the message this run carried, and that estimate comes
    // out whether or not the reading changes.
    if (found.runId == _measured?.runId) {
      _releaseEstimate(releasing);
      return;
    }

    _measured = found;
    _inFlightTokens = _afterReleasing(releasing);
    // The window is here because a null one is why an otherwise measured
    // thread shows no percentage — whether the model declares none or
    // the room has not loaded yet, which this cannot tell apart.
    _logger.info(
      'Context reading measured',
      attributes: {
        'threadId': _threadId,
        'runId': found.runId,
        'finalInputTokens': found.finalInputTokens,
        'finalOutputTokens': found.finalOutputTokens,
        'contextWindow': contextWindow,
      },
    );
    notifyListeners();
  }

  int _afterReleasing(int tokens) {
    final remaining = _inFlightTokens - tokens;
    return remaining < 0 ? 0 : remaining;
  }

  /// Drops [tokens] of the in-flight estimate without a new measurement.
  void _releaseEstimate(int tokens) {
    if (_disposed) return;
    final remaining = _afterReleasing(tokens);
    if (remaining == _inFlightTokens) return;

    _inFlightTokens = remaining;
    notifyListeners();
  }

  /// Records what is currently in the composer.
  ///
  /// Debounced: the draft is the only term that moves while someone is
  /// typing, and it costs a rebuild rather than a request.
  void draftChanged(String draft, {int images = 0}) {
    _draftDebounce.run(() {
      if (_disposed) return;

      final estimate = estimateDraftTokens(draft, images: images);

      if (estimate == _draftTokens) return;

      _draftTokens = estimate;
      notifyListeners();
    });
  }

  /// Records that the draft has been sent.
  ///
  /// The message is on its way to the model but no run has reported on
  /// it yet, so simply dropping the draft term would make the gauge read
  /// *low* for as long as the run takes — the one direction it must
  /// never read. The estimate holds the sent message's place instead,
  /// and is released when the run's measurement arrives.
  void draftSent(String text, {int images = 0}) {
    // Estimated from what is being sent, not from what the debounce last
    // stored: a paste and an immediate send both land inside the window,
    // and the stored draft is still empty when the message goes.
    _draftDebounce.cancel();

    _inFlightTokens += estimateDraftTokens(text, images: images);
    _draftTokens = 0;

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _draftDebounce.cancel();
    super.dispose();
  }
}
