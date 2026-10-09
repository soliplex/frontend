import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/static_thinking_block.dart';
import 'copy_button.dart';
import 'execution/thinking_block.dart';
import 'message_caption.dart';
import 'notice_bubble.dart';
import 'package:soliplex_design/soliplex_design.dart';

class NoResponseTileWidget extends StatelessWidget {
  const NoResponseTileWidget({
    super.key,
    required this.roomId,
    required this.message,
    this.runId,
    this.onReportRun,
    this.executionTracker,
    this.streamingPhase,
    required this.besideReply,
  });

  final String roomId;
  final NoResponseTile message;

  /// The run this tile reports on, or null when none could be resolved.
  final String? runId;

  /// Opens the note the run carries, for reading, extending or replacing.
  final void Function(String runId)? onReportRun;

  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  /// Whether this reports how a run ended beside the reply that stands in for
  /// it. The reply carries the run's work and its author, so this shows only
  /// the reason, the note affordance, the time and the copy button. Reasoning
  /// after the reply renders in a band: the reply's own within its response,
  /// or, in a later response, the run's unclaimed band, which makes the
  /// outcome stand in for the run instead.
  final bool besideReply;

  @override
  Widget build(BuildContext context) {
    final reportLabel = _reportLabel(message.reason);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!besideReply) ..._standingIn(Theme.of(context)),
        _TerminalReasonBubble(
          reason: message.reason,
          errorDetail: message.errorDetail,
          besideReply: besideReply,
        ),
        if (reportLabel != null && runId != null && onReportRun != null)
          SoliplexButton.text(
            isCompact: true,
            onPressed: () => onReportRun!(runId!),
            child: Text(reportLabel),
          ),
        if (message.createdAt != null) MessageCaption(time: message.createdAt!),
        if (message.errorDetail case final detail?
            when detail.trim().isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s1),
          CopyButton(text: detail),
        ],
      ],
    );
  }

  /// What the tile shows when it stands in for its run: the run's work, its
  /// reasoning, and who the notice speaks for.
  List<Widget> _standingIn(ThemeData theme) {
    final hasTracker = executionTracker != null;
    return [
      if (streamingPhase != null) PhaseIndicator(phase: streamingPhase!),
      if (hasTracker)
        ExecutionTimeline(
          roomId: roomId,
          messageId: message.id,
          tracker: executionTracker!,
        ),
      if (hasTracker)
        ExecutionThinkingBlock(
          roomId: roomId,
          messageId: message.id,
          tracker: executionTracker!,
        )
      else if (message.hasThinkingText)
        StaticThinkingBlock(
          roomId: roomId,
          messageId: message.id,
          text: message.thinkingText,
        ),
      Text(
        'Assistant',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: SoliplexSpacing.s1),
    ];
  }
}

/// What the report affordance offers for a run that ended this way, or null
/// when it offers nothing.
///
/// Derived from the tile's own reason rather than stored, so it survives the
/// tile being scrolled out of the sliver's cache extent, a thread switch, a
/// history reload and a restart.
///
/// A `failed` tile belongs to a run that failed, and the registry attempts to
/// auto-file a failed run for the reasons it files, so a note often exists —
/// but the POST is best-effort and a tile replayed from history may predate any attempt, so
/// the label describes the affordance rather than a stored record, and the
/// dialog copes with finding nothing. Nothing is filed for `finished` at
/// all — but a run that ends saying nothing is a failure from the user's point
/// of view, and a common thing to report.
String? _reportLabel(TerminalReason reason) => switch (reason) {
      TerminalReason.failed => 'View or add a note',
      TerminalReason.finished => 'Report a problem',
      // The user stopped this themselves; there is nothing to tell them.
      TerminalReason.cancelled => null,
    };

class _TerminalReasonBubble extends StatelessWidget {
  const _TerminalReasonBubble({
    required this.reason,
    this.errorDetail,
    required this.besideReply,
  });

  final TerminalReason reason;
  final String? errorDetail;
  final bool besideReply;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (reason) {
      TerminalReason.finished => (
          Icons.info_outline,
          'Run finished without a response',
        ),
      TerminalReason.failed => (
          Icons.error_outline,
          switch ((errorDetail, besideReply)) {
            (final detail?, _) when detail.trim().isNotEmpty =>
              'Run failed: $detail',
            // The reply above it is the run's response.
            (_, true) => 'Run failed',
            (_, false) => 'Run failed without a response',
          },
        ),
      TerminalReason.cancelled => (
          Icons.cancel_outlined,
          'Run cancelled without a response',
        ),
    };
    return NoticeBubble(icon: icon, label: label);
  }
}
