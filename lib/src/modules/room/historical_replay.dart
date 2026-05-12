import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_tracker.dart';

/// Signature for the per-event AG-UI → execution-event bridger. The
/// production implementation is the top-level [bridgeBaseEvent] from
/// `soliplex_agent`; tests inject throwing variants to exercise the
/// per-event catch in [replayToTrackers].
typedef ExecutionBridge = ExecutionEvent? Function(BaseEvent event);

final Logger _logger = LogManager.instance.getLogger(
  'soliplex_frontend.historical_replay',
);

/// Replays stored AG-UI event bundles into one frozen [ExecutionTracker]
/// per assistant message, keyed by that message's id.
///
/// Bundle classification:
///
/// - **Normal**: contains an assistant `TextMessageStart`. Events bucket
///   under that id; any events accumulated in the hoisted `pending` from
///   prior tool-yield bundles drain into the first assistant bucket.
/// - **Tool-yield**: contains a `ToolCallStart` but no assistant
///   `TextMessageStart`. Events flow into the hoisted `pending` so the
///   next normal bundle's first assistant message absorbs them.
/// - **No-response**: neither assistant `TextMessageStart` nor
///   `ToolCallStart`. Bucket events (including any prior pending) under
///   [noResponseMessageId] for the run so the synthesized no-response
///   tile has a tracker to attach to.
///
/// A throw from [bridge] is logged at error and the offending event
/// skipped so surrounding events in the same bundle still bucket
/// correctly. The drop is deliberately UI-silent: chat-message
/// boundaries mint the drop tile; double-minting from this tracker
/// projection would surface the same backend event as two tiles.
/// [bridge] defaults to [bridgeBaseEvent] and is overridable for tests.
Map<String, ExecutionTracker> replayToTrackers(
  List<RunEventBundle> runs, {
  @visibleForTesting ExecutionBridge bridge = bridgeBaseEvent,
}) {
  final buckets = <String, List<ExecutionEvent>>{};
  // Hoisted across bundles: tool-yield events accumulate here until the
  // next normal bundle's first assistant message absorbs them.
  final pending = <ExecutionEvent>[];

  ExecutionEvent? bridgeOrLog(BaseEvent raw) {
    try {
      return bridge(raw);
    } on Object catch (e, st) {
      _logger.error(
        'bridge threw on ${raw.runtimeType}; event skipped',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  for (final bundle in runs) {
    final hasAssistantStart = bundle.events.any(
      (e) => e is TextMessageStartEvent && e.role == .assistant,
    );
    final hasToolCall = bundle.events.any((e) => e is ToolCallStartEvent);

    if (hasAssistantStart) {
      String? currentMessageId;
      for (final raw in bundle.events) {
        if (raw is TextMessageStartEvent && raw.role == .assistant) {
          final messageId = raw.messageId;
          currentMessageId = messageId;
          final bucket = buckets.putIfAbsent(messageId, () => []);
          if (pending.isNotEmpty) {
            bucket.addAll(pending);
            pending.clear();
          }
        }

        final execEvent = bridgeOrLog(raw);
        if (execEvent == null) continue;

        if (currentMessageId != null) {
          buckets.putIfAbsent(currentMessageId, () => []).add(execEvent);
        } else {
          pending.add(execEvent);
        }
      }
    } else if (hasToolCall) {
      for (final raw in bundle.events) {
        final execEvent = bridgeOrLog(raw);
        if (execEvent == null) continue;
        pending.add(execEvent);
      }
    } else {
      final synthesizedId = noResponseMessageId(bundle.runId);
      final bucket = buckets.putIfAbsent(synthesizedId, () => []);
      if (pending.isNotEmpty) {
        bucket.addAll(pending);
        pending.clear();
      }
      for (final raw in bundle.events) {
        final execEvent = bridgeOrLog(raw);
        if (execEvent == null) continue;
        bucket.add(execEvent);
      }
    }
  }

  // A trailing tool-yield bundle's hoisted events have no follow-up
  // assistant message to absorb them; the warning makes the drop
  // observable instead of silent.
  if (pending.isNotEmpty) {
    _logger.warning(
      'Dropping unattached events from a trailing tool-yield bundle '
      '(no follow-up bundle).',
      attributes: {'pendingCount': pending.length},
    );
  }

  return {
    for (final entry in buckets.entries)
      entry.key: ExecutionTracker.historical(
        events: entry.value,
        logger: _logger,
      ),
  };
}
