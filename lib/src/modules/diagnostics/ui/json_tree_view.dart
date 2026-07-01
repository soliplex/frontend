import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../models/json_tree_model.dart';

/// Renders a [List<JsonNode>] as an expandable tree with syntax coloring.
class JsonTreeView extends StatelessWidget {
  const JsonTreeView({
    required this.nodes,
    this.selectable = true,
    super.key,
  });

  final List<JsonNode> nodes;

  /// Whether the tree's text manages its own selection (via `SelectableText`).
  /// Pass `false` when rendered inside a `SelectionArea` so the surrounding
  /// area handles selection — a self-selecting widget nested in a
  /// `SelectionArea` drops out of the area's selection.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      final theme = Theme.of(context);
      return Text(
        '(empty)',
        style: context.monospaceOn(theme.textTheme.bodySmall).copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
      );
    }
    // Deep nesting (left indent) and long unbroken values (tokens, URLs) would
    // otherwise clip off the right edge on narrow screens. A horizontal scroll
    // lets the tree extend to its natural width and pan instead.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _JsonNodeList(nodes: nodes, depth: 0, selectable: selectable),
    );
  }
}

class _JsonNodeList extends StatelessWidget {
  const _JsonNodeList({
    required this.nodes,
    required this.depth,
    required this.selectable,
  });

  final List<JsonNode> nodes;
  final int depth;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes)
          _JsonNodeTile(node: node, depth: depth, selectable: selectable),
      ],
    );
  }
}

class _JsonNodeTile extends StatefulWidget {
  const _JsonNodeTile({
    required this.node,
    required this.depth,
    required this.selectable,
  });

  final JsonNode node;
  final int depth;
  final bool selectable;

  @override
  State<_JsonNodeTile> createState() => _JsonNodeTileState();
}

class _JsonNodeTileState extends State<_JsonNodeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final indent = widget.depth * SoliplexSpacing.s4;

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
          label: node.key.isEmpty
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

    final baseStyle = context.monospaceOn(theme.textTheme.bodySmall);

    final span = TextSpan(
      children: [
        if (node.key.isNotEmpty)
          TextSpan(
            text: '${node.key}: ',
            style: baseStyle.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        TextSpan(
          text: node.value,
          style: baseStyle.copyWith(color: valueColor),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: widget.selectable ? SelectableText.rich(span) : Text.rich(span),
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
    final baseStyle = context.monospaceOn(theme.textTheme.bodySmall);

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
                const SizedBox(width: SoliplexSpacing.s1),
                widget.selectable
                    ? SelectableText(
                        _expanded ? expandedLabel : label,
                        style: baseStyle,
                      )
                    : Text(
                        _expanded ? expandedLabel : label,
                        style: baseStyle,
                      ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          _JsonNodeList(
            nodes: children,
            depth: widget.depth + 1,
            selectable: widget.selectable,
          ),
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: widget.selectable
                ? SelectableText(closingLabel, style: baseStyle)
                : Text(closingLabel, style: baseStyle),
          ),
        ],
      ],
    );
  }
}
