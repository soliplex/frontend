import 'package:flutter/material.dart';

import '../board_render_state.dart';

class TicTacToeCell extends StatelessWidget {
  const TicTacToeCell({
    required this.render,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final CellRender render;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        render.isWinning ? Theme.of(context).colorScheme.primary : null;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          color: color?.withValues(alpha: 0.1),
        ),
        alignment: Alignment.center,
        child: render.mark == null
            ? null
            : Text(
                render.mark!,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: render.isPending
                          ? Theme.of(context).colorScheme.outline
                          : color,
                    ),
              ),
      ),
    );
  }
}
