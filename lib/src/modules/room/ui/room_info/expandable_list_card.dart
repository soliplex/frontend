import 'package:flutter/material.dart';

import 'room_info_widgets.dart';

class ExpandableTile extends StatelessWidget {
  const ExpandableTile({
    super.key,
    required this.name,
    required this.expanded,
    required this.onToggle,
    this.content,
  });

  final String name;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContent = content != null;

    final nameRow = Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hasContent)
          Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
      ],
    );

    return GestureDetector(
      onTap: hasContent ? onToggle : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            nameRow,
            if (expanded && hasContent)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: content,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ExpandableListCard<T> extends StatefulWidget {
  const ExpandableListCard({
    required this.title,
    required this.items,
    required this.nameOf,
    required this.contentOf,
    this.emptyLabel,
    super.key,
  });

  final String title;
  final List<T> items;
  final String Function(T) nameOf;
  final Widget? Function(T) contentOf;
  final String? emptyLabel;

  @override
  State<ExpandableListCard<T>> createState() => _ExpandableListCardState<T>();
}

class _ExpandableListCardState<T> extends State<ExpandableListCard<T>> {
  final _expandedNames = <String>{};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return SectionCard(
      title: '${widget.title} (${items.length})',
      children:
          items.isEmpty
              ? [
                EmptyMessage(
                  label: widget.emptyLabel ?? widget.title.toLowerCase(),
                ),
              ]
              : [
                for (final item in items)
                  () {
                    final name = widget.nameOf(item);
                    return ExpandableTile(
                      name: name,
                      expanded: _expandedNames.contains(name),
                      onToggle:
                          () => setState(() {
                            if (!_expandedNames.remove(name)) {
                              _expandedNames.add(name);
                            }
                          }),
                      content: widget.contentOf(item),
                    );
                  }(),
              ],
    );
  }
}
