import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class ThreadTile extends StatelessWidget {
  const ThreadTile({
    super.key,
    required this.thread,
    required this.isSelected,
    required this.onTap,
  });

  final ThreadInfo thread;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: isSelected,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      title: Text(
        thread.hasName ? thread.name : 'Untitled',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _formatRelativeTime(thread.createdAt),
        style: theme.textTheme.bodySmall,
      ),
      dense: true,
      onTap: onTap,
    );
  }

  static String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
  }
}
