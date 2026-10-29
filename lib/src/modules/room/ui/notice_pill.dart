import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// How long a success notice stays before dismissing itself.
const successNoticeDismissDelay = Duration(seconds: 4);

/// Fades a [NoticePill] in and out as [child] changes. A pill keyed by its
/// message cross-fades when the message changes.
class AnimatedNoticePill extends StatelessWidget {
  const AnimatedNoticePill({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: child,
    );
  }
}

/// A one-line notice with a close button and an optional action.
class NoticePill extends StatelessWidget {
  const NoticePill({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : assert(
          (actionLabel == null) == (onAction == null),
          'actionLabel and onAction are given together or not at all',
        );

  final IconData icon;
  final Color background;
  final Color foreground;
  final String message;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(
          left: SoliplexSpacing.s3, bottom: SoliplexSpacing.s1),
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.lg),
      ),
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: SoliplexSpacing.s2),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: SoliplexSpacing.s1),
            // A text button paints in primary, which a brand accent can make
            // unreadable on [background]; [foreground] is the color made to
            // read on it.
            Theme(
              data: theme.copyWith(
                colorScheme: theme.colorScheme.copyWith(primary: foreground),
              ),
              child: SoliplexButton.text(
                onPressed: onAction,
                isCompact: true,
                child: Text(actionLabel),
              ),
            ),
          ],
          const SizedBox(width: SoliplexSpacing.s1),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            tooltip: 'Dismiss',
            color: foreground,
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
