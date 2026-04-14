import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../execution_tracker.dart';
import '../../../../../soliplex_frontend.dart';
import '../copy_button.dart';

class ExecutionThinkingBlock extends StatefulWidget {
  const ExecutionThinkingBlock({super.key, required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<ExecutionThinkingBlock> createState() => _ExecutionThinkingBlockState();
}

class _ExecutionThinkingBlockState extends State<ExecutionThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thinkingBlocks = widget.tracker.thinkingBlocks.watch(context);
    final isStreaming = widget.tracker.isThinkingStreaming.watch(context);
    if (thinkingBlocks.isEmpty && !isStreaming) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
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
                    const SizedBox(width: 6),
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
