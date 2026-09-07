import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../../core/util/debouncer.dart';

/// Holds the context reading for one thread, and refreshes it.
///
/// The measurement itself is not computed here. It is taken from the
/// provider, through the backend, which is the only vantage point that
/// sees the whole request: the agent's instructions, capability
/// instructions, tool and MCP schemas, the chat template, images, and
/// any evidence compaction applied on the way out. Attempting to
/// reconstruct that here would necessarily read low, because MCP tool
/// schemas are only knowable by connecting to the MCP server.
///
/// What this adds locally is the draft — the one part of a reading that
/// nothing has measured, because it has not been sent. Its estimate is
/// biased high on purpose; see [estimateDraftTokens].
///
/// Refreshing is a cold path. The measurement only changes when a run
/// finishes, so it is fetched on thread open and after each run, never
/// while someone types.
/// Wire names for the segment kinds the backend reports.
///
/// A name the backend adds but this does not know is dropped rather
/// than lumped into a neighbour, so an unrecognised slice goes missing
/// from the pie instead of quietly inflating another one.
const _kindsByName = <String, SegmentKind>{
  'userText': SegmentKind.userText,
  'assistantText': SegmentKind.assistantText,
  'toolCallArguments': SegmentKind.toolCallArguments,
  'toolResult': SegmentKind.toolResult,
  'compactedReceipt': SegmentKind.compactedReceipt,
  'compactedCapsule': SegmentKind.compactedCapsule,
  'overhead': SegmentKind.overhead,
};

class ContextUsageController extends ChangeNotifier {
  /// Creates a controller for [threadId] in [roomId].
  ContextUsageController({
    required SoliplexApi api,
    required String roomId,
    required String threadId,
    Duration draftDebounce = const Duration(milliseconds: 300),
  })  : _api = api,
        _roomId = roomId,
        _threadId = threadId,
        _draftDebounce = Debouncer(draftDebounce);

  final SoliplexApi _api;
  final String _roomId;
  final String _threadId;
  final Debouncer _draftDebounce;

  ThreadContext _context = const ThreadContext.unknown();
  int _draftTokens = 0;
  int _inFlightTokens = 0;
  bool _disposed = false;

  /// The current reading.
  ///
  /// [ContextUsage.contextWindow] is null whenever the provider does not
  /// report one, which is what makes the gauge hide itself rather than
  /// render against an invented denominator.
  ContextUsage get usage {
    final measured = _context.measuredTokens;
    final unmeasured = _draftTokens + _inFlightTokens;

    if (measured == null && unmeasured == 0) {
      return const ContextUsage.unknown();
    }

    return ContextUsage(
      tokens: (measured ?? 0) + unmeasured,
      byKind: _byKind(),
      contextWindow: _context.maxModelLen,
      // The thread's own tokens are the provider's count, not an
      // approximation, and the estimated terms are over-stated rather
      // than under-stated. Nothing here is waiting on more evidence.
      isProvisional: false,
      isExact: measured != null && unmeasured == 0,
    );
  }

  /// The breakdown, translated to the kinds the UI groups by.
  ///
  /// The estimated terms are folded in as user text: that is what a
  /// draft is, and what a sent-but-unmeasured message was.
  Map<SegmentKind, int> _byKind() {
    final measured = _context.tokensByKind;

    if (measured.isEmpty) return const {};

    final byKind = <SegmentKind, int>{};

    for (final entry in measured.entries) {
      final kind = _kindsByName[entry.key];

      if (kind == null) continue;

      byKind[kind] = (byKind[kind] ?? 0) + entry.value;
    }

    final unmeasured = _draftTokens + _inFlightTokens;

    if (unmeasured > 0) {
      byKind[SegmentKind.userText] =
          (byKind[SegmentKind.userText] ?? 0) + unmeasured;
    }

    return byKind;
  }

  /// The most recent reading fetched from the backend.
  ThreadContext get threadContext => _context;

  /// Re-reads the measurement from the backend.
  ///
  /// Call on thread open and when a run finishes. Failure is silent by
  /// design: a context indicator that cannot refresh should keep showing
  /// its last honest reading, not interrupt the conversation.
  ///
  /// [detail] additionally asks where the tokens went, which costs the
  /// backend a tokenizer call per stored message. It belongs to opening
  /// the breakdown, not to drawing the gauge.
  Future<void> refresh({bool detail = false}) async {
    final ThreadContext found;

    try {
      found = await _api.getThreadContext(
        _roomId,
        _threadId,
        detail: detail,
      );
    } on Exception {
      return;
    }

    if (_disposed) return;

    // The run that carried the sent message has been measured, so the
    // estimate standing in for it is no longer needed.
    final settled = _inFlightTokens != 0 &&
        found.measuredAtRunId != _context.measuredAtRunId;

    if (found == _context && !settled) return;

    if (settled) _inFlightTokens = 0;

    _context = found;
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
  /// and is released when a newer run's measurement arrives.
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
