import 'dart:convert';

import 'package:flutter/material.dart';

import '../copy_button.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';

/// Styled scrollable block for displaying a raw/JSON payload as plain monospace text.
class ArgsBlock extends StatefulWidget {
  const ArgsBlock({
    super.key,
    required this.raw,
    this.indent = 0,
    this.accentColor,
  });

  /// Full raw string — never truncated; content scrolls.
  final String raw;

  final double indent;

  /// Optional left-border accent (used to distinguish results from args).
  final Color? accentColor;

  @override
  State<ArgsBlock> createState() => _ArgsBlockState();
}

class _ArgsBlockState extends State<ArgsBlock> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static String _prettyPrint(String s) {
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return _renderMap(obj, 0);
      if (obj is String) return obj;
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return s;
    }
  }

  static String _renderMap(Map<String, dynamic> map, int depth) {
    final pad = '  ' * depth;
    final parts = <String>[];
    for (final e in map.entries) {
      final v = e.value;
      if (v is String && v.contains('\n')) {
        final indented =
            v.trimRight().split('\n').map((l) => '$pad  $l').join('\n');
        parts.add('$pad${e.key}:\n$indented');
      } else if (v is Map<String, dynamic>) {
        parts.add('$pad${e.key}:\n${_renderMap(v, depth + 1)}');
      } else if (v is List) {
        final json = const JsonEncoder.withIndent('  ').convert(v);
        final indented = json.split('\n').map((l) => '$pad  $l').join('\n');
        parts.add('$pad${e.key}:\n$indented');
      } else {
        parts.add('$pad${e.key}: $v');
      }
    }
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = _prettyPrint(widget.raw);

    return Padding(
      padding: EdgeInsets.only(left: widget.indent, top: 4, bottom: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.accentColor != null
                    ? widget.accentColor!.withValues(alpha: 0.1)
                    : theme.colorScheme.surfaceContainerHigh,
                border: widget.accentColor != null
                    ? Border(
                        left: BorderSide(color: widget.accentColor!, width: 3),
                      )
                    : null,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CopyButton(text: widget.raw, iconSize: 14),
                ],
              ),
            ),
            // scrollable monospace body
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: SelectableText(
                    display,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: monospaceFont(Theme.of(context).platform),
                      fontFamilyFallback: const ['monospace'],
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
