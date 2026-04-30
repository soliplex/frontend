import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../room/room_providers.dart';
import '../tic_tac_toe_controller.dart';
import '../tic_tac_toe_intent.dart';
import '../tic_tac_toe_providers.dart';
import '../tic_tac_toe_state.dart';

class TicTacToeToolbarButton extends ConsumerWidget {
  const TicTacToeToolbarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(roomActiveThreadProvider);
    if (active == null) {
      final spawn = ref.watch(roomSpawnNewThreadProvider);
      if (spawn == null) return const SizedBox.shrink();
      return IconButton(
        tooltip: 'Play tic-tac-toe',
        icon: const Icon(Icons.grid_3x3),
        onPressed: () => spawn(
          prompt: 'Start a new game.',
          stateOverlay: {
            '_inbox': {
              TicTacToeIntent.surfaceKey: {
                TicTacToeIntent.intentKey: TicTacToeIntent.newGame,
              },
            },
          },
        ),
      );
    }
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
      return IconButton(
        tooltip: render == null ? 'Play tic-tac-toe' : 'Toggle board',
        icon: const Icon(Icons.grid_3x3),
        onPressed: () {
          if (render == null) {
            controller.newGame();
            return;
          }
          final s = controller.state.value;
          controller.setViewMode(
            s.viewMode == TicTacToeViewMode.hidden
                ? TicTacToeViewMode.inline
                : TicTacToeViewMode.hidden,
          );
        },
      );
    });
  }
}
