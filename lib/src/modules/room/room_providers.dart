import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'message_expansions.dart';
import 'run_registry.dart';

final messageExpansionsProvider = Provider<MessageExpansions>(
  name: 'messageExpansionsProvider',
  (_) => throw StateError(
    'messageExpansionsProvider was read without an override. '
    'In production this is wired by roomModule(); in tests, wrap the '
    'widget in `ProviderScope(overrides: [messageExpansionsProvider'
    '.overrideWithValue(MessageExpansions())])`.',
  ),
);

/// Builders contributed by other modules to render between the message
/// list and the chat input. Defaults to empty; modules override via
/// ProviderScope to inject their widgets (e.g., the tic-tac-toe board).
final roomAboveChatInputBuildersProvider = Provider<List<WidgetBuilder>>(
  name: 'roomAboveChatInputBuildersProvider',
  (_) => const [],
);

/// Builders contributed by other modules to render as extra icons in the
/// chat input toolbar. Defaults to empty; modules override via
/// ProviderScope.
final roomChatInputToolbarBuildersProvider = Provider<List<WidgetBuilder>>(
  name: 'roomChatInputToolbarBuildersProvider',
  (_) => const [],
);

/// Currently-active thread in the room view. Null when no thread is
/// selected. Set by the room screen as it switches threads. Other
/// modules read this to attach per-thread controllers.
final roomActiveThreadProvider =
    Provider<({ThreadKey threadKey, AgentRuntime runtime})?>(
  name: 'roomActiveThreadProvider',
  (_) => null,
);

/// The room module's RunRegistry, exposed for cross-module observers
/// (e.g., TicTacToeController watching for chat streaming events).
/// Constructed and overridden by RoomAppModule.build().
final runRegistryProvider = Provider<RunRegistry>(
  name: 'runRegistryProvider',
  (_) => throw StateError(
    'runRegistryProvider was read without an override. '
    'In production this is wired by RoomAppModule.build(); in tests, '
    'override with the test registry.',
  ),
);
