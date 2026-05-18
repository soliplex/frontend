import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../../../soliplex_frontend.dart';
import '../../compute_display_messages.dart' show loadingMessageId;
import '../../execution_tracker.dart';
import '../../message_expansions.dart' show MessageExpansion;
import '../../room_providers.dart';
import '../copy_button.dart';

class ExecutionThinkingBlock extends ConsumerStatefulWidget {
  const ExecutionThinkingBlock({
    super.key,
    required this.roomId,
    required this.messageId,
    required this.tracker,
  });

  final String roomId;
  final String messageId;
  final ExecutionTracker tracker;

  @override
  ConsumerState<ExecutionThinkingBlock> createState() =>
      _ExecutionThinkingBlockState();
}

class _ExecutionThinkingBlockState
    extends ConsumerState<ExecutionThinkingBlock> {
  // Thinking-block expansion while messageId == loadingMessageId. Kept
  // local (not in the store) because the sentinel is reused across runs —
  // persisting under it would leak open/closed state into the next
  // response.
  bool _loadingPhaseThinking = false;

  // Null during the AwaitingText sentinel phase, because loadingMessageId
  // is reused across runs and persisting under it would leak state into
  // the next response. Captured once in initState; the AwaitingText →
  // TextStreaming transition remounts this widget under a real messageId
  // (see MessageTimeline's per-id ValueKey), at which point [_expansion]
  // becomes non-null for the rest of its life.
  MessageExpansion? _expansion;

  @override
  void initState() {
    super.initState();
    if (widget.messageId == loadingMessageId) return;
    _expansion = ref
        .read(messageExpansionsProvider)
        .forMessage(widget.roomId, widget.messageId);
  }

  bool get _expanded => _expansion?.thinkingExpanded ?? _loadingPhaseThinking;

  void _toggle() {
    setState(() {
      final next = !_expanded;
      if (_expansion != null) {
        _expansion!.thinkingExpanded = next;
      } else {
        _loadingPhaseThinking = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thinkingBlocks = widget.tracker.thinkingBlocks.watch(context);
    final isStreaming = widget.tracker.isThinkingStreaming.watch(context);
    if (thinkingBlocks.isEmpty && !isStreaming) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.onSurfaceVariant,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SoliplexSpacing.s1),
                  Text(
                    thinkingBlocks.length > 1
                        ? 'Thinking (${thinkingBlocks.length})'
                        : 'Thinking',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(width: SoliplexSpacing.s2),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const Spacer(),
                  CopyButton(
                    text: thinkingBlocks.join('\n\n'),
                    tooltip: 'Copy thinking',
                    iconSize: 16,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: SoliplexSpacing.s1),
                for (var i = 0; i < thinkingBlocks.length; i++) ...[
                  if (thinkingBlocks[i].isNotEmpty) ...[
                    if (i > 0) const SizedBox(height: SoliplexSpacing.s2),
                    Text(
                      thinkingBlocks[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
