import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Wraps [child] so a long-press (touch) or secondary-tap (right-click) offers
/// a single "Mark as read" action at the pointer. Used by the rooms rail circle
/// and the lobby room cards, which have no room for a persistent menu button.
/// A null [onMarkRead] disables the gesture (e.g. the item is already read).
class MarkReadContextMenu extends StatelessWidget {
  const MarkReadContextMenu({
    super.key,
    required this.child,
    required this.onMarkRead,
    this.title,
  });

  final Widget child;

  /// Marks the wrapped item read. Null disables the gesture — no menu opens.
  final VoidCallback? onMarkRead;

  /// Optional heading shown above the action, so a long-press still surfaces a
  /// label where [child] has none visible — the rail's single-letter avatar
  /// passes the room name here. Null shows just the action (the lobby cards,
  /// which already show the room name, pass nothing).
  final String? title;

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    final onMarkRead = this.onMarkRead;
    if (onMarkRead == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final title = this.title;
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (title != null) ...[
          PopupMenuItem(
            enabled: false,
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_chat_read_outlined, size: 20),
              SizedBox(width: SoliplexSpacing.s3),
              Text('Mark as read'),
            ],
          ),
        ),
      ],
    );
    if (selected ?? false) onMarkRead();
  }

  @override
  Widget build(BuildContext context) {
    // When disabled, add no gesture recognizer at all, so a long-press
    // affordance on [child] (e.g. a Tooltip) still works. An always-present
    // detector would also enter the gesture arena and could win the long-press
    // over the child, suppressing it for nothing.
    if (onMarkRead == null) return child;
    return GestureDetector(
      onLongPressStart: (d) => _show(context, d.globalPosition),
      onSecondaryTapDown: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
}
