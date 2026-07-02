import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Wraps [child] so a long-press (touch) or secondary-tap (right-click) offers
/// a single "Mark as read" action at the pointer. Used by the rooms rail circle
/// and the lobby room cards, which have no room for a persistent menu button.
/// When [enabled] is false the gesture opens nothing (e.g. already read).
class MarkReadContextMenu extends StatelessWidget {
  const MarkReadContextMenu({
    super.key,
    required this.child,
    required this.enabled,
    required this.onMarkRead,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onMarkRead;

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    if (!enabled) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
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
    return GestureDetector(
      onLongPressStart: (d) => _show(context, d.globalPosition),
      onSecondaryTapDown: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
}
