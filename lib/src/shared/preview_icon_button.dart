import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Compact eye-icon affordance for "open a preview / viewer for this
/// row". Mirrors the visual weight of [CopyButton]: bare icon, hover
/// tooltip, no surrounding chrome — so it sits cleanly alongside other
/// trailing row actions.
class PreviewIconButton extends StatelessWidget {
  const PreviewIconButton({
    super.key,
    required this.onTap,
    this.tooltip = 'Preview',
    this.iconSize = 16,
  }) : assert(iconSize > 0);

  /// Null disables the button. Mirrors the convention of [IconButton].
  final VoidCallback? onTap;
  final String tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(soliplexRadii.sm),
          child: Icon(Icons.visibility_outlined, size: iconSize, color: color),
        ),
      ),
    );
  }
}
