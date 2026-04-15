import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.message});
  final ToolCallMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final toolCall in message.toolCalls)
          _ToolCallCard(toolCall: toolCall),
      ],
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.toolCall});
  final ToolCallInfo toolCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ExpansionTile(
        leading: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
        title: Row(
          children: [
            Flexible(
              child: Text(
                toolCall.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              toolCall.status.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        dense: true,
        children: [
          if (toolCall.hasArguments) ..._argumentBlocks(toolCall),
          if (toolCall.hasResult)
            _CodeBlock(label: 'Result', text: toolCall.result),
        ],
      ),
    );
  }

  List<Widget> _argumentBlocks(ToolCallInfo toolCall) {
    final raw = toolCall.arguments;
    if (raw.isEmpty) return const [];

    // Python tools: show the code directly, not JSON-wrapped.
    const pythonTools = {'run_script', 'repl_python', 'execute_python'};
    if (pythonTools.contains(toolCall.name)) {
      try {
        final args = jsonDecode(raw) as Map<String, dynamic>;
        final code = args['code'] as String?;
        if (code != null) return [_CodeBlock(label: 'Code', text: code)];
      } catch (_) {}
    }

    // All other tools: pretty-print the JSON so it's readable.
    try {
      final decoded = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return [_CodeBlock(label: 'Arguments', text: encoder.convert(decoded))];
    } catch (_) {
      return [_CodeBlock(label: 'Arguments', text: raw)];
    }
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.label, required this.text});
  final String label;
  final String text;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              _copied
                  ? Text(
                      'Copied',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : InkWell(
                      onTap: _copy,
                      borderRadius: BorderRadius.circular(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              widget.text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
