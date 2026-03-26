import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'message_tile.dart';
import 'streaming_tile.dart';

class MessageTimeline extends StatelessWidget {
  const MessageTimeline({
    super.key,
    required this.messages,
    required this.messageStates,
    this.streamingState,
    this.executionTracker,
    this.room,
    this.onSuggestionTapped,
  });

  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;
  final StreamingState? streamingState;
  final ExecutionTracker? executionTracker;
  final Room? room;
  final void Function(String suggestion)? onSuggestionTapped;

  @override
  Widget build(BuildContext context) {
    final itemCount = messages.length + (streamingState != null ? 1 : 0);
    if (itemCount == 0) {
      return _EmptyState(room: room, onSuggestionTapped: onSuggestionTapped);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final isStreamingItem = index == messages.length;
        if (isStreamingItem) {
          return StreamingTile(
            key: const ValueKey('streaming'),
            streamingState: streamingState!,
            executionTracker: executionTracker,
          );
        }
        return MessageTile(
          key: ValueKey(messages[index].id),
          message: messages[index],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.room, this.onSuggestionTapped});

  final Room? room;
  final void Function(String suggestion)? onSuggestionTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (room == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48,
                color: theme.colorScheme.outline.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              'Type a message to get started',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room!.name.isNotEmpty)
              Text(
                room!.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            if (room!.welcomeMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  room!.welcomeMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (room!.suggestions.isNotEmpty) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final suggestion in room!.suggestions)
                      ActionChip(
                        label: Text(suggestion),
                        onPressed: onSuggestionTapped != null
                            ? () => onSuggestionTapped!(suggestion)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            if (!room!.hasWelcomeMessage && !room!.hasSuggestions) ...[
              Icon(Icons.chat_bubble_outline,
                  size: 48,
                  color: theme.colorScheme.outline.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'Type a message to get started',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
