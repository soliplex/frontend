import 'package:flutter/material.dart';

import '../models/format_utils.dart';
import '../models/http_event_group.dart';
import 'http_status_display.dart';

class HttpEventTile extends StatelessWidget {
  const HttpEventTile({
    required this.group,
    this.dense = false,
    this.isSelected = false,
    this.onTap,
    super.key,
  });

  final HttpEventGroup group;
  final bool dense;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Semantics(
      label: group.semanticLabel,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12,
          vertical: dense ? 6 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRequestLine(theme),
            SizedBox(height: dense ? 2 : 4),
            _buildResultLine(theme),
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }

  Widget _buildRequestLine(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final selectedColor = colorScheme.onPrimaryContainer;

    final methodStyle = (dense
            ? theme.textTheme.bodySmall
            : theme.textTheme.bodyMedium)
        ?.copyWith(
          fontWeight: FontWeight.bold,
          color: isSelected ? selectedColor : colorScheme.primary,
        );

    final pathStyle = (dense
            ? theme.textTheme.bodySmall
            : theme.textTheme.bodyMedium)
        ?.copyWith(color: isSelected ? selectedColor : null);

    return Row(
      children: [
        Text(group.methodLabel, style: methodStyle),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            group.pathWithQuery,
            style: pathStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildResultLine(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color:
          isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
      fontSize: dense ? 11 : null,
    );

    return Row(
      children: [
        if (!dense) ...[
          Text(group.timestamp.toHttpTimeString(), style: metaStyle),
          const SizedBox(width: 4),
          Text('→', style: metaStyle),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: HttpStatusDisplay(group: group, isSelected: isSelected),
        ),
      ],
    );
  }
}
