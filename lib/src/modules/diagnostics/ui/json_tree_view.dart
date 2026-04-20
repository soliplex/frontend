import 'package:flutter/material.dart';

import '../models/json_tree_model.dart';

/// Renders a [List<JsonNode>] as an expandable tree with syntax coloring.
class JsonTreeView extends StatelessWidget {
  const JsonTreeView({required this.nodes, super.key});

  final List<JsonNode> nodes;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return Text(
        '(empty)',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return _JsonNodeList(nodes: nodes, depth: 0);
  }
}

class _JsonNodeList extends StatelessWidget {
  const _JsonNodeList({required this.nodes, required this.depth});

  final List<JsonNode> nodes;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes) _JsonNodeTile(node: node, depth: depth),
      ],
    );
  }
}

class _JsonNodeTile extends StatefulWidget {
  const _JsonNodeTile({required this.node, required this.depth});

  final JsonNode node;
  final int depth;

  @override
  State<_JsonNodeTile> createState() => _JsonNodeTileState();
}

class _JsonNodeTileState extends State<_JsonNodeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final indent = widget.depth * 16.0;

    return switch (node) {
      ValueNode() => _buildValueRow(context, node, indent),
      ObjectNode() => _buildExpandable(
        context,
        node,
        indent,
        label: node.key.isEmpty ? '{…}' : '${node.key}: {…}',
        expandedLabel: node.key.isEmpty ? '{' : '${node.key}: {',
        closingLabel: '}',
        children: node.children,
      ),
      ArrayNode() => _buildExpandable(
        context,
        node,
        indent,
        label:
            node.key.isEmpty
                ? '[${node.itemCount}]'
                : '${node.key}: [${node.itemCount}]',
        expandedLabel: node.key.isEmpty ? '[' : '${node.key}: [',
        closingLabel: ']',
        children: node.children,
      ),
    };
  }

  Widget _buildValueRow(BuildContext context, ValueNode node, double indent) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? valueColor;
    if (node.value == 'null') {
      valueColor = colorScheme.onSurfaceVariant;
    } else if (node.value == 'true' || node.value == 'false') {
      valueColor = colorScheme.tertiary;
    } else {
      // Heuristic: if it looks like a number, use primary color.
      final asDouble = double.tryParse(node.value);
      if (asDouble != null) valueColor = colorScheme.primary;
    }

    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
    );

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SelectableText.rich(
        TextSpan(
          children: [
            if (node.key.isNotEmpty)
              TextSpan(
                text: '${node.key}: ',
                style: baseStyle?.copyWith(color: colorScheme.onSurface),
              ),
            TextSpan(
              text: node.value,
              style: baseStyle?.copyWith(color: valueColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandable(
    BuildContext context,
    JsonNode node,
    double indent, {
    required String label,
    required String expandedLabel,
    required String closingLabel,
    required List<JsonNode> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: indent),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                SelectableText(
                  _expanded ? expandedLabel : label,
                  style: baseStyle,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          _JsonNodeList(nodes: children, depth: widget.depth + 1),
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: SelectableText(closingLabel, style: baseStyle),
          ),
        ],
      ],
    );
  }
}
