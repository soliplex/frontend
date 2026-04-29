import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../room/room_providers.dart';
import '../board_render_state.dart';
import '../tic_tac_toe_controller.dart';
import '../tic_tac_toe_providers.dart';
import '../tic_tac_toe_server_state.dart';
import '../tic_tac_toe_state.dart';
import 'tic_tac_toe_cell.dart';
import 'tic_tac_toe_controls.dart';
import 'tic_tac_toe_fullscreen_page.dart';

class TicTacToeBoard extends ConsumerStatefulWidget {
  const TicTacToeBoard({super.key});

  @override
  ConsumerState<TicTacToeBoard> createState() => _TicTacToeBoardState();
}

class _TicTacToeBoardState extends ConsumerState<TicTacToeBoard> {
  TicTacToeViewMode _lastSeenMode = TicTacToeViewMode.hidden;

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(roomActiveThreadProvider);
    if (active == null) return const SizedBox.shrink();
    final registry = ref.watch(tictactoeRegistryProvider);
    final runRegistry = ref.watch(runRegistryProvider);
    final controller = registry.controllerFor(
      active.threadKey,
      () => TicTacToeController(
        threadKey: active.threadKey,
        runtime: active.runtime,
        runRegistry: runRegistry,
      ),
    );

    return Watch((_) {
      final render = controller.boardRender.value;
      final s = controller.state.value;

      if (s.viewMode != _lastSeenMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleViewModeTransition(_lastSeenMode, s.viewMode, controller);
          _lastSeenMode = s.viewMode;
        });
      }

      if (render == null) return const SizedBox.shrink();
      if (s.viewMode == TicTacToeViewMode.hidden ||
          s.viewMode == TicTacToeViewMode.fullscreen) {
        return const SizedBox.shrink();
      }
      return _BoardContent(
        controller: controller,
        render: render,
        clientState: s,
      );
    });
  }

  void _handleViewModeTransition(
    TicTacToeViewMode prev,
    TicTacToeViewMode next,
    TicTacToeController controller,
  ) {
    if (next == TicTacToeViewMode.fullscreen &&
        prev != TicTacToeViewMode.fullscreen) {
      Navigator.of(context)
          .push(
        MaterialPageRoute<void>(
          builder: (_) => TicTacToeFullscreenPage(controller: controller),
        ),
      )
          .then((_) {
        if (controller.state.value.viewMode == TicTacToeViewMode.fullscreen) {
          controller.setViewMode(TicTacToeViewMode.inline);
        }
      });
    } else if (prev == TicTacToeViewMode.fullscreen &&
        next != TicTacToeViewMode.fullscreen) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }
}

class _BoardContent extends StatelessWidget {
  const _BoardContent({
    required this.controller,
    required this.render,
    required this.clientState,
  });

  final TicTacToeController controller;
  final BoardRenderState render;
  final TicTacToeClientState clientState;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (render.winner != null) _ResultBanner(winner: render.winner!),
            for (int r = 0; r < 3; r++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int c = 0; c < 3; c++)
                    TicTacToeCell(
                      key: Key('cell-$r-$c'),
                      render: render.cells[r][c],
                      enabled: !render.inFlight &&
                          render.winner == null &&
                          render.cells[r][c].mark == null,
                      onTap: () => controller.clickCell(r, c),
                    ),
                ],
              ),
            if (render.winner != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton(
                  onPressed: render.canNewGame ? controller.newGame : null,
                  child: const Text('Play again'),
                ),
              ),
            const SizedBox(height: 8),
            TicTacToeControls(
              render: render,
              autoSend: clientState.autoSend,
              lastError: clientState.lastError,
              onSend: controller.send,
              onCancel: controller.cancel,
              onUndo: controller.clickUndo,
              onRedo: controller.clickRedo,
              onToggleAutoSend: controller.toggleAutoSend,
              onToggleFullscreen: () => controller.setViewMode(
                clientState.viewMode == TicTacToeViewMode.fullscreen
                    ? TicTacToeViewMode.inline
                    : TicTacToeViewMode.fullscreen,
              ),
              onRetry: controller.send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.winner});

  final TicTacToeOutcome winner;

  @override
  Widget build(BuildContext context) {
    final text = switch (winner) {
      TicTacToeOutcome.user => 'You win!',
      TicTacToeOutcome.agent => 'Agent wins.',
      TicTacToeOutcome.draw => "It's a draw.",
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
