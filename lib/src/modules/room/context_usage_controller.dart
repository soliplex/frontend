import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../../core/util/debouncer.dart';

/// Holds the context reading for one thread.
///
/// Two numbers, from two places, neither computed here:
///
/// - The window is the room's. It is fixed for the life of the backend
///   process and arrives with the room, so it is given once at
///   construction rather than fetched.
/// - The measurement is the provider's own count for the last request of
///   the newest measured run. It arrives with the thread's history, and
///   after each run from that run's usage record. The backend is the only
///   vantage point that sees the whole request — instructions, tool and
///   MCP schemas, the chat template, images, evidence compaction — so
///   reconstructing it here would necessarily read low.
///
/// What this adds locally is the draft — the one part of a reading that
/// nothing has measured, because it has not been sent. Its estimate is
/// biased high on purpose; see [estimateDraftTokens].
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
  /// case the gauge hides itself rather than render against an invented
  /// denominator.
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

  /// The current reading.
  ContextUsage get usage {
    final measured = _measured?.finalInputTokens;
    final unmeasured = _draftTokens + _inFlightTokens;

    if (measured == null && unmeasured == 0) {
      return const ContextUsage.unknown();
    }

    return ContextUsage(
      tokens: (measured ?? 0) + unmeasured,
      contextWindow: contextWindow,
      // Exact only while nothing estimated is folded in: the thread's
      // own tokens are the provider's own count, but a draft is not.
      isExact: measured != null && unmeasured == 0,
    );
  }

  /// The newest measured run's usage, or null before any run has been.
  RunUsage? get measured => _measured;

  /// Takes the measurement from a freshly loaded [history].
  ///
  /// Called when the thread's history loads. The history already carries
  /// the newest measured run, so this costs no request.
  void historyLoaded(ThreadHistory history) {
    if (_disposed) return;
    _measure(history.latestUsage);
  }

  /// Re-reads the measurement once [runId] has ended.
  ///
  /// The history is not re-read after a run, so the run's own usage is
  /// fetched. Failure is silent by design: a context indicator that
  /// cannot refresh should keep showing its last honest reading, not
  /// interrupt the conversation. So is a run that recorded nothing — it
  /// never reached the model, and the previous reading still stands.
  Future<void> runEnded(String runId) async {
    final RunUsage? found;

    try {
      found = await _api.getRunUsage(_roomId, _threadId, runId);
    } on Exception {
      _release();
      return;
    }

    if (_disposed) return;

    _measure(found);
  }

  void _measure(RunUsage? found) {
    // A newer run has been measured, so the estimate standing in for the
    // sent message is no longer needed. A run that measured nothing
    // releases it too: the message either never reached the model or is
    // already inside the previous reading, and holding an estimate
    // against a run that has ended would read high for good.
    final settled =
        found != null && found.isMeasured && found.runId != _measured?.runId;

    if (settled) {
      _measured = found;
      _inFlightTokens = 0;
      notifyListeners();
      return;
    }

    _release();
  }

  /// Drops the in-flight estimate without a new measurement.
  void _release() {
    if (_disposed || _inFlightTokens == 0) return;

    _inFlightTokens = 0;
    notifyListeners();
  }

  /// Records what is currently in the composer.
  ///
  /// Debounced: the draft is the only term that moves while someone is
  /// typing, and it costs a rebuild rather than a request.
  void draftChanged(String draft) {
    _draftDebounce.run(() {
      if (_disposed) return;

      final estimate = estimateDraftTokens(draft);

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
  void draftSent() {
    _draftDebounce.cancel();

    _inFlightTokens += _draftTokens;
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
