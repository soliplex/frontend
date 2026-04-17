import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Compact header strip showing aggregate queue health from the HTTP
/// concurrency limiter.
///
/// Renders nothing until the limiter has emitted at least one event
/// (i.e. at least one HTTP request has acquired a slot).
class ConcurrencySummaryPanel extends StatelessWidget {
  const ConcurrencySummaryPanel({required this.events, super.key});

  final List<ConcurrencyWaitEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    final stats = _ConcurrencyStats.from(events);
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'queued ${stats.queuedCount} of ${stats.total}',
                  style: labelStyle,
                ),
                Text(
                  'peak slots ${stats.peakSlotsInUse} / max depth '
                  '${stats.maxDepthAtEnqueue}',
                  style: labelStyle,
                ),
                if (stats.queuedCount > 0)
                  Text('avg ${stats.avgWaitMs}ms', style: labelStyle),
                if (stats.maxWaitMs > 0)
                  Text('max ${stats.maxWaitMs}ms', style: labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConcurrencyStats {
  const _ConcurrencyStats({
    required this.total,
    required this.queuedCount,
    required this.maxDepthAtEnqueue,
    required this.peakSlotsInUse,
    required this.avgWaitMs,
    required this.maxWaitMs,
  });

  factory _ConcurrencyStats.from(List<ConcurrencyWaitEvent> events) {
    var maxDepth = 0;
    var peakSlots = 0;
    var maxWaitMs = 0;
    var queuedWaitSumMs = 0;
    var queuedCount = 0;

    for (final e in events) {
      maxDepth = math.max(maxDepth, e.queueDepthAtEnqueue);
      peakSlots = math.max(peakSlots, e.slotsInUseAfterAcquire);
      final waitMs = e.waitDuration.inMilliseconds;
      maxWaitMs = math.max(maxWaitMs, waitMs);
      if (e.waitDuration > Duration.zero) {
        queuedWaitSumMs += waitMs;
        queuedCount++;
      }
    }

    return _ConcurrencyStats(
      total: events.length,
      queuedCount: queuedCount,
      maxDepthAtEnqueue: maxDepth,
      peakSlotsInUse: peakSlots,
      avgWaitMs: queuedCount == 0 ? 0 : queuedWaitSumMs ~/ queuedCount,
      maxWaitMs: maxWaitMs,
    );
  }

  final int total;
  final int queuedCount;
  final int maxDepthAtEnqueue;
  final int peakSlotsInUse;
  final int avgWaitMs;
  final int maxWaitMs;
}
