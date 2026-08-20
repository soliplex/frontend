import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';

/// One icon-and-label row inside a popup menu, so every ⋮ menu in the app is
/// styled the same and a row added to one does not have to be styled again in
/// the others.
class MenuRow extends StatelessWidget {
  const MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Tints the row with `colorScheme.error` for a destructive action.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: SoliplexSpacing.s3),
        // Flexible so a long label can't overflow the menu's width; the menu
        // widens to fit when there's room.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
