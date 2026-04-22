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
