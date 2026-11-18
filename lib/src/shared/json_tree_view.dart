import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';
import 'content/code_view.dart';
import 'json_tree_model.dart';

/// Renders a [List<JsonNode>] as an expandable tree, coloured by each value's
/// JSON type in the same highlight theme as [CodeView].
class JsonTreeView extends StatelessWidget {
  const JsonTreeView({
    required this.nodes,
    this.selectable = true,
    super.key,
  });

  final List<JsonNode> nodes;

  /// Whether the tree manages its own selection: its rows share one
  /// `SelectionArea`, so a drag can select across rows. Pass `false` when
  /// rendered inside a `SelectionArea` so the surrounding area handles
  /// selection; a `SelectionArea` nested in another keeps its selection apart
  /// from the outer one's.
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
    final tree = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: _JsonNodeList(nodes: nodes, depth: 0),
    );
    // Replaces the ambient style so prose line height and letter spacing do
    // not reach the tree, keeping its rows as tall as CodeView's lines.
    return DefaultTextStyle(
      style: codeTextStyle(context),
      child: selectable ? SelectionArea(child: tree) : tree,
    );
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
    final indent = widget.depth * SoliplexSpacing.s4;
    final theme = codeTheme(context);

    return switch (node) {
      ValueNode() => _buildValueRow(theme, node, indent),
      ObjectNode() => _buildExpandable(
          context,
          theme,
          node,
          indent,
          collapsed: '{…}',
          opening: '{',
          closing: '}',
          children: node.children,
        ),
      ArrayNode() => _buildExpandable(
          context,
          theme,
          node,
          indent,
          collapsed: '[${node.itemCount}]',
          opening: '[',
          closing: ']',
          children: node.children,
        ),
    };
  }

  Widget _buildValueRow(
    Map<String, TextStyle> theme,
    ValueNode node,
    double indent,
  ) {
    final value = node.value;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Text.rich(
        TextSpan(
          children: [
            ..._keySpans(theme, node.key),
            TextSpan(
              text: value is String ? '"$value"' : '$value',
              style: _valueStyle(theme, value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandable(
    BuildContext context,
    Map<String, TextStyle> theme,
    JsonNode node,
    double indent, {
    required String collapsed,
    required String opening,
    required String closing,
    required List<JsonNode> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

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
                Text.rich(
                  TextSpan(
                    children: [
                      ..._keySpans(theme, node.key),
                      TextSpan(text: _expanded ? opening : collapsed),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          _JsonNodeList(nodes: children, depth: widget.depth + 1),
          Padding(
            padding: EdgeInsets.only(left: indent),
            child: Text(closing),
          ),
        ],
      ],
    );
  }
}

/// The highlight theme's style for a JSON [value]. A null style, like a
/// missing theme entry, leaves the text in the inherited plain-text style.
TextStyle? _valueStyle(Map<String, TextStyle> theme, Object? value) =>
    switch (value) {
      String() => theme['string'],
      num() => theme['number'],
      bool() || null => theme['literal'],
      _ => null,
    };

List<InlineSpan> _keySpans(Map<String, TextStyle> theme, String key) => [
      if (key.isNotEmpty) ...[
        TextSpan(text: key, style: theme['attr']),
        const TextSpan(text: ': '),
      ],
    ];
