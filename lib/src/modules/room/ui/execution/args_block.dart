import 'dart:convert';

import 'package:flutter/material.dart';

import '../copy_button.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';

/// Styled scrollable block for displaying a raw/JSON payload as rendered markdown.
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

  static String _toMarkdown(String s) {
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return _mapToMarkdown(obj);
      if (obj is String) return obj;
      return const JsonEncoder.withIndent('  ').convert(obj);
    } catch (_) {
      return s;
    }
  }

  static String _mapToMarkdown(Map<String, dynamic> map) {
    final parts = <String>[];
    for (final e in map.entries) {
      final v = e.value;
      if (v is String && v.contains('\n')) {
        parts.add('${e.key}:\n\n```\n${v.trimRight()}\n```');
      } else if (v is Map || v is List) {
        final json = const JsonEncoder.withIndent('  ').convert(v);
        parts.add('${e.key}:\n\n```json\n$json\n```');
      } else {
        parts.add('${e.key}: $v');
      }
    }
    return parts.join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = _toMarkdown(widget.raw);

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
            // scrollable markdown body
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: FlutterMarkdownPlusRenderer(data: display),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
