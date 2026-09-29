import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// What the banner says for [warning].
String threadStateWarningText(ThreadStateWarning warning) => switch (warning) {
      ThreadStateWarning.legacyCitations =>
        "This thread was saved by an older version. Sources for its earlier "
            "answers can't be shown.",
      ThreadStateWarning.scopeUnreadable =>
        "This thread's saved document or database selection couldn't be "
            'read, so answers from now on may search more than earlier '
            'answers did.',
      ThreadStateWarning.stateIncomplete =>
        "Some of this thread's earlier results couldn't be restored, so later "
            'answers may miss them. Starting a new thread avoids this.',
      ThreadStateWarning.sourcesSkipped =>
        "Some sources for earlier answers couldn't be shown.",
    };

/// Tells the user part of this thread's stored state could not be used as
/// stored — one line per warning, in declaration order.
class ThreadStateWarningBanner extends StatelessWidget {
  const ThreadStateWarningBanner({
    required this.warnings,
    required this.onDismiss,
    super.key,
  });

  final Set<ThreadStateWarning> warnings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.of(context).colors;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: colors.onWarningContainer);
    return Container(
      width: double.infinity,
      // Several lines on a short screen (keyboard up, landscape, large text)
      // would otherwise leave the timeline above it no height; they scroll.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height / 3,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      color: colors.warningContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: colors.onWarningContainer,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in ThreadStateWarning.values)
                    if (warnings.contains(warning))
                      Text(threadStateWarningText(warning), style: style),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
