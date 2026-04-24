import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../soliplex_frontend.dart';
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
        padding: const EdgeInsets.all(SoliplexSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentRoom.name.isNotEmpty)
              Text(
                currentRoom.name,
                style: theme.textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
            if (currentRoom.hasWelcomeMessage) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FlutterMarkdownPlusRenderer(
                  data: currentRoom.welcomeMessage,
                ),
              ),
            ],
            if (currentRoom.hasSuggestions) ...[
              const SizedBox(height: SoliplexSpacing.s6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: SoliplexSpacing.s2,
                  runSpacing: SoliplexSpacing.s2,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final suggestion in currentRoom.suggestions)
                      _SuggestionChip(
                        label: suggestion,
                        onTap: onSuggestionTapped != null
                            ? () => onSuggestionTapped!(suggestion)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            if (currentRoom.hasQuizzes) ...[
              const SizedBox(height: SoliplexSpacing.s6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.quiz,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: SoliplexSpacing.s2),
                        Text(
                          currentRoom.quizzes.length == 1
                              ? 'Quiz Available'
                              : '${currentRoom.quizzes.length} Quizzes Available',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: SoliplexSpacing.s2),
                    Wrap(
                      spacing: SoliplexSpacing.s2,
                      runSpacing: SoliplexSpacing.s2,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final entry in currentRoom.quizzes.entries)
                          ActionChip(
                            avatar: Icon(Icons.play_arrow,
                                size: 16, color: theme.colorScheme.onPrimary),
                            label: Text(entry.value),
                            labelStyle: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                            backgroundColor: theme.colorScheme.primary,
                            side: BorderSide.none,
                            onPressed: onQuizTapped != null
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
            padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s4, vertical: SoliplexSpacing.s1),
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
