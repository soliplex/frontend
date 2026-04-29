import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'message_expansions.dart';

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
