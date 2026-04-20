import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'markdown/flutter_markdown_plus_renderer.dart';

class RoomWelcome extends StatelessWidget {
  const RoomWelcome({
    super.key,
    this.room,
    this.onSuggestionTapped,
    this.onQuizTapped,
    required this.fallback,
  });

  final Room? room;
  final void Function(String suggestion)? onSuggestionTapped;
  final void Function(String quizId)? onQuizTapped;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final currentRoom = room;
    if (currentRoom == null) return fallback;

    if (!currentRoom.hasWelcomeMessage &&
        !currentRoom.hasSuggestions &&
        !currentRoom.hasQuizzes) {
      return fallback;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentRoom.name.isNotEmpty)
              Text(
                currentRoom.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            if (currentRoom.hasWelcomeMessage) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FlutterMarkdownPlusRenderer(
                  data: currentRoom.welcomeMessage,
                ),
              ),
            ],
            if (currentRoom.hasSuggestions) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final suggestion in currentRoom.suggestions)
                      _SuggestionChip(
                        label: suggestion,
                        onTap:
                            onSuggestionTapped != null
                                ? () => onSuggestionTapped!(suggestion)
                                : null,
                      ),
                  ],
                ),
              ),
            ],
            if (currentRoom.hasQuizzes) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.quiz,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currentRoom.quizzes.length == 1
                              ? 'Quiz Available'
                              : '${currentRoom.quizzes.length} Quizzes Available',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final entry in currentRoom.quizzes.entries)
                          ActionChip(
                            avatar: const Icon(Icons.play_arrow, size: 16),
                            label: Text(entry.value),
                            onPressed:
                                onQuizTapped != null
                                    ? () => onQuizTapped!(entry.key)
                                    : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
        ),
      ),
    );
  }
}
