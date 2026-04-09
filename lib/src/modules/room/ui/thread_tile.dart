import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

enum _ThreadAction { rename, delete }

class ThreadTile extends StatefulWidget {
  const ThreadTile({
    super.key,
    required this.thread,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ThreadInfo thread;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<ThreadTile> {
  bool _isHovered = false;

  static bool get _isDesktop => switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMenu = widget.isSelected || _isHovered || !_isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ListTile(
        selected: widget.isSelected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        title: Text(
          widget.thread.hasName ? widget.thread.name : 'Untitled',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatRelativeTime(widget.thread.createdAt),
          style: theme.textTheme.bodySmall,
        ),
        dense: true,
        onTap: widget.onTap,
        trailing: showMenu ? _buildMenu(theme) : null,
      ),
    );
  }

  Widget _buildMenu(ThemeData theme) {
    return PopupMenuButton<_ThreadAction>(
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Thread options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (action) {
        switch (action) {
          case _ThreadAction.rename:
            widget.onRename();
          case _ThreadAction.delete:
            widget.onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _ThreadAction.rename,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: 12),
              Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ThreadAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline,
                  size: 18, color: theme.colorScheme.error),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
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
