import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

/// Key the band nothing has claimed is published under, so the tile standing
/// in for a reply that has not arrived can find it.
const awaitingTrackerKey = '_awaiting';

/// Manages execution bands: the stretch of work between one thing the
/// assistant said and the next.
///
/// A band opens with no name, because the message it belongs to has not spoken
/// yet. It is held apart from the named ones rather than stored under
/// [awaitingTrackerKey]: a sentinel key let the next run overwrite it in
/// silence, left one behind after every run, and made claiming it a rename
/// after the fact. Naming it is the same act whoever does it — a reply that
/// speaks, or a tile synthesized for a run that never did.
class TrackerRegistry {
  TrackerRegistry({required Logger logger}) : _logger = logger;

  /// Bands that belong to a message, by its id.
  final Map<String, ExecutionTracker> _named = {};

  /// The band nothing has claimed yet. At most one exists.
  ExecutionTracker? _unclaimed;

  /// The named band still collecting, if any. Never set while [_unclaimed] is.
  String? _openId;

  final Logger _logger;

  Map<String, ExecutionTracker> get trackers => Map.unmodifiable({
        ..._named,
        if (_unclaimed != null) awaitingTrackerKey: _unclaimed!,
      });

  /// Update tracker state based on the current streaming state.
  ///
  /// [events] is the execution event signal to subscribe a new tracker
  /// to, only used when a tracker needs to be created. [activities] is
  /// the live `Conversation.activities` signal the new tracker mirrors
  /// into a local copy, so that freezing it pins the records it had at
  /// that moment.
  void onStreaming(
    StreamingState streaming,
    ReadonlySignal<ExecutionEvent?> events,
    ReadonlySignal<List<ActivityRecord>> activities,
  ) {
    switch (streaming) {
      case TextStreaming(:final messageId, :final text):
        // A band goes to a message once it has said something. A response
        // that begins with a tool call opens a message with nothing in it,
        // purely to give that call's `parentMessageId` something to refer to,
        // and its work belongs to the reply that eventually speaks.
        if (text.trim().isEmpty) return;
        if (_openId == messageId) return;
        final band = _unclaimed;
        if (band == null) {
          // Text with no band open: a message opening while another is still
          // streaming, which the protocol forbids and the event processor
          // warns about. Keep it under its own id rather than losing it.
          _closeOpen();
        }
        _claim(
          messageId,
          band ??
              ExecutionTracker(
                executionEvents: events,
                activities: activities,
                logger: _logger,
              ),
        );
      case AwaitingText():
        // A message that has spoken closes its band when its text ends; what
        // happens next belongs to whatever is said after it, so a new one
        // opens here.
        if (_unclaimed != null) return;
        _closeOpen();
        _unclaimed = ExecutionTracker(
          executionEvents: events,
          activities: activities,
          logger: _logger,
        );
    }
  }

  /// Freeze the band still collecting, and report one the run leaves with
  /// nothing to render it.
  ///
  /// Every band is meant to reach a tile: a reply's own, or the one
  /// synthesized for a run that never spoke, which [claimOpenBand] hands it to
  /// before this runs. What is left is work the user watched happen and will
  /// not find again, so it is reported rather than dropped in silence — and
  /// then dropped, because nothing will ever render it.
  void onRunTerminated({String? runId}) {
    final band = _unclaimed;
    if (band != null) {
      final events = band.timeline.value;
      if (events.isNotEmpty) {
        _logger.warning(
          'Run ended with execution events no tile claims; they will not '
          'render.',
          attributes: {
            'events': events.length,
            if (runId != null) 'runId': runId,
          },
        );
      }
      band.freeze();
      _unclaimed = null;
    }
    _closeOpen();
  }

  /// Hands the band nothing has claimed to [messageId] — what a reply does by
  /// speaking, done here for the tile synthesized for a run that did not.
  ///
  /// Called by `ExecutionTrackerExtension` on the terminal transitions of a
  /// run whose conversation holds such a tile. With no band open the tile
  /// still renders its own `thinkingText`, but no execution steps attach; the
  /// warning makes that divergence observable.
  void claimOpenBand(String messageId) {
    final band = _unclaimed;
    if (band == null) {
      _logger.warning(
        'No open band to hand over; the tile will render thinking but no '
        'execution steps.',
        attributes: {'messageId': messageId},
      );
      return;
    }
    _claim(messageId, band);
  }

  /// Puts [band] under [messageId] and leaves it collecting.
  ///
  /// A band already under that key loses. That happens when a message speaks
  /// twice with another in between — the protocol forbids it and the event
  /// processor warns — so the replaced band holds work that will not render.
  /// Freezing rather than dropping it releases its subscription to the event
  /// signal.
  void _claim(String messageId, ExecutionTracker band) {
    _unclaimed = null;
    final displaced = _named[messageId];
    if (displaced != null) {
      displaced.freeze();
      _logger.warning(
        'A band already under this message id was replaced; its events will '
        'not render.',
        attributes: {'messageId': messageId},
      );
    }
    _named[messageId] = band;
    _openId = messageId;
  }

  void _closeOpen() {
    if (_openId == null) return;
    _named[_openId!]?.freeze();
    _openId = null;
  }

  /// Bulk-inserts already-frozen trackers produced from a loaded thread's
  /// history. Existing entries with the same key are not overwritten —
  /// a live tracker always wins over a historical one.
  void seedHistorical(Map<String, ExecutionTracker> historical) {
    for (final entry in historical.entries) {
      _named.putIfAbsent(entry.key, () => entry.value);
    }
  }

  void dispose() {
    for (final tracker in _named.values) {
      tracker.dispose();
    }
    _named.clear();
    _unclaimed?.dispose();
    _unclaimed = null;
    _openId = null;
  }
}
