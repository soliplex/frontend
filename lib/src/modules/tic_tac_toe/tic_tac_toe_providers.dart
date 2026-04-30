import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tic_tac_toe_registry.dart';

/// Registry holding one TicTacToeController per active ThreadKey.
/// Constructed and overridden by TicTacToeAppModule.build().
final tictactoeRegistryProvider = Provider<TicTacToeRegistry>(
  name: 'tictactoeRegistryProvider',
  (_) => throw StateError(
    'tictactoeRegistryProvider was read without an override. '
    'In production this is wired by TicTacToeAppModule.build(); in '
    'tests, wrap the widget in `ProviderScope(overrides: ['
    'tictactoeRegistryProvider.overrideWithValue(...)])`.',
  ),
);
