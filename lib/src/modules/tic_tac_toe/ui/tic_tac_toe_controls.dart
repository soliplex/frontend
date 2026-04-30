import 'package:flutter/material.dart';

import '../board_render_state.dart';
import '../tic_tac_toe_state.dart';

class TicTacToeControls extends StatelessWidget {
  const TicTacToeControls({
    required this.render,
    required this.autoSend,
    required this.lastError,
    required this.isFullscreen,
    required this.unreadCount,
    required this.onSend,
    required this.onCancel,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleAutoSend,
    required this.onToggleFullscreen,
    required this.onRetry,
    super.key,
  });

  final BoardRenderState render;
  final bool autoSend;
  final TicTacToeError? lastError;

  /// True when the controls are rendered inside the fullscreen page.
  /// Drives the toggle button's icon + tooltip + unread badge.
  final bool isFullscreen;

  /// Unread chat-message count accumulated while in fullscreen. The
  /// badge is hidden when the count is zero.
  final int unreadCount;

  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onToggleAutoSend;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lastError != null) _ErrorChip(error: lastError!, onRetry: onRetry),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: render.canUndo ? onUndo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: render.canRedo ? onRedo : null,
            ),
            if (render.canCancel)
              ElevatedButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              )
            else
              ElevatedButton(
                onPressed: render.canSend ? onSend : null,
                child: const Text('Send'),
              ),
            Row(
              children: [
                const Text('Auto'),
                Switch(value: autoSend, onChanged: (_) => onToggleAutoSend()),
              ],
            ),
            Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: IconButton(
                tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                icon: Icon(
                  isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                onPressed: onToggleFullscreen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.error, required this.onRetry});

  final TicTacToeError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = switch (error) {
      TicTacToeError.network => "Couldn't reach the server.",
      TicTacToeError.toolRejected => 'Move was rejected.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        key: const Key('tictactoe-error-chip'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
