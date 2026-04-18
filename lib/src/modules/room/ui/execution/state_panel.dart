import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../execution_tracker.dart';
import '../copy_button.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';

class StatePanel extends StatefulWidget {
  const StatePanel({super.key, required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<StatePanel> createState() => _StatePanelState();
}

class _StatePanelState extends State<StatePanel> {
  bool _open = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.tracker.aguiState.watch(context);
    if (state.isEmpty) return const SizedBox.shrink();

    final json = const JsonEncoder.withIndent('  ').convert(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Show state',
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(
                _open ? Icons.info : Icons.info_outline,
                size: 20,
                color: _open
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'State',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    CopyButton(text: json, iconSize: 14),
                  ],
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: SelectableText(
                        json,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: monospaceFont(Theme.of(context).platform),
                          fontFamilyFallback: const ['monospace'],
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
