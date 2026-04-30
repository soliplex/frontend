import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../tic_tac_toe_controller.dart';
import '../tic_tac_toe_state.dart';
import 'tic_tac_toe_cell.dart';
import 'tic_tac_toe_controls.dart';

class TicTacToeFullscreenPage extends StatelessWidget {
  const TicTacToeFullscreenPage({required this.controller, super.key});

  final TicTacToeController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Watch((_) {
          final render = controller.boardRender.value;
          final s = controller.state.value;
          if (render == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int r = 0; r < 3; r++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int c = 0; c < 3; c++)
                            TicTacToeCell(
                              key: Key('fs-cell-$r-$c'),
                              render: render.cells[r][c],
                              enabled: !render.inFlight &&
                                  render.winner == null &&
                                  render.cells[r][c].serverMark == null,
                              onTap: () => controller.clickCell(r, c),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TicTacToeControls(
                      render: render,
                      autoSend: s.autoSend,
                      lastError: s.lastError,
                      isFullscreen: true,
                      unreadCount: s.unreadChatWhileFullscreen,
                      onSend: controller.send,
                      onCancel: controller.cancel,
                      onUndo: controller.clickUndo,
                      onRedo: controller.clickRedo,
                      onToggleAutoSend: controller.toggleAutoSend,
                      onToggleFullscreen: () =>
                          controller.setViewMode(TicTacToeViewMode.inline),
                      onRetry: controller.send,
                    ),
                  ],
                ),
              ),
              if (s.bannerVisible)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${s.unreadChatWhileFullscreen} new chat '
                              'message(s)',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: controller.dismissBanner,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}
