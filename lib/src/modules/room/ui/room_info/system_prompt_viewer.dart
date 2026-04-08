import 'package:flutter/material.dart';

import '../../../../../soliplex_frontend.dart';
import '../../../../shared/copy_button.dart';

class SystemPromptViewer extends StatefulWidget {
  const SystemPromptViewer({super.key, required this.prompt});
  final String prompt;

  @override
  State<SystemPromptViewer> createState() => _SystemPromptViewerState();
}

class _SystemPromptViewerState extends State<SystemPromptViewer> {
  bool _expanded = false;

  static const _collapsedMaxLines = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'System Prompt',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              CopyButton(
                iconSize: 18,
                text: widget.prompt,
                tooltip: 'Copy system prompt',
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          LayoutBuilder(
            builder: (context, constraints) {
              final promptStyle = SoliplexTheme.mergeCode(
                context,
                theme.textTheme.bodyMedium,
              ).copyWith(fontSize: 14);
              const containerPadding = 16.0;
              final overflows = !_expanded &&
                  (TextPainter(
                    text: TextSpan(
                      text: widget.prompt,
                      style: promptStyle,
                    ),
                    maxLines: _collapsedMaxLines,
                    textDirection: TextDirection.ltr,
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(
                          maxWidth: constraints.maxWidth - containerPadding,
                        ))
                      .didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    child: SelectableText(
                      widget.prompt,
                      maxLines: _expanded ? null : _collapsedMaxLines,
                      style: promptStyle,
                    ),
                  ),
                  if (overflows || _expanded)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Collapse' : 'Expand'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
