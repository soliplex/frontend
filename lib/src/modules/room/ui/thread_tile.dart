import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import '../../lobby/ui/unread_dot.dart';

enum _ThreadAction { markRead, rename, delete }

class ThreadTile extends StatefulWidget {
  const ThreadTile({
    super.key,
    required this.thread,
    required this.isSelected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onMarkRead,
    this.isRunning = false,
    this.unread = false,
  });

  final ThreadInfo thread;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// Stamps this thread read. Offered in the overflow menu only when [unread].
  final VoidCallback onMarkRead;
  final bool isRunning;

  /// Whether the thread has activity newer than the user last saw — shows a
  /// leading [UnreadDot]. The selected thread is never marked unread.
  final bool unread;

  @override
  State<ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<ThreadTile> {
  bool _isHovered = false;
  bool _isMenuOpen = false;

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
    final showMenu =
        widget.isSelected || _isHovered || _isMenuOpen || !_isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ListTile(
        selected: widget.isSelected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        title: Row(
          children: [
            if (widget.unread) ...[
              const UnreadDot(),
              const SizedBox(width: SoliplexSpacing.s2),
            ],
            Expanded(
              child: Text(
                widget.thread.hasName ? widget.thread.name : 'New Thread',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          formatRelativeTime(widget.thread.createdAt),
          style: theme.textTheme.bodySmall,
        ),
        dense: true,
        onTap: widget.onTap,
        trailing: _buildTrailing(theme, showMenu: showMenu),
      ),
    );
  }

  Widget? _buildTrailing(ThemeData theme, {required bool showMenu}) {
    if (widget.isRunning) return _buildSpinner(theme);
    if (showMenu) return _buildMenu(theme);
    return null;
  }

  Widget _buildSpinner(ThemeData theme) {
    return SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: theme.colorScheme.primary,
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
      // Keep the menu button "shown" while the popup overlay is open, so
      // the button isn't unmounted when the pointer leaves the tile. If the
      // button unmounts while the popup is open, the showMenu future's
      // completion callback short-circuits on `!mounted` and silently drops
      // onSelected for non-selected threads on desktop.
      onOpened: () => setState(() => _isMenuOpen = true),
      onCanceled: () => setState(() => _isMenuOpen = false),
      onSelected: (action) {
        setState(() => _isMenuOpen = false);
        switch (action) {
          case _ThreadAction.markRead:
            widget.onMarkRead();
          case _ThreadAction.rename:
            widget.onRename();
          case _ThreadAction.delete:
            widget.onDelete();
        }
      },
      itemBuilder: (context) => [
        if (widget.unread)
          const PopupMenuItem(
            value: _ThreadAction.markRead,
            child: Row(
              children: [
                Icon(Icons.mark_chat_read_outlined, size: 18),
                SizedBox(width: SoliplexSpacing.s3),
                Text('Mark as read'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: _ThreadAction.rename,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: SoliplexSpacing.s3),
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
              SizedBox(width: SoliplexSpacing.s3),
              Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}
