import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_design/soliplex_design.dart';

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

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s6),
        // Spacing sits on the Column so gaps fall only between the sections
        // that actually render — any of them can be absent.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: SoliplexSpacing.s6,
          children: [
            // The room name is not repeated here: the room header carries it
            // in every layout, and this block sits directly beneath it.
            if (currentRoom.hasWelcomeMessage)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: FlutterMarkdownPlusRenderer(
                  data: currentRoom.welcomeMessage,
                ),
              ),
            if (currentRoom.hasSuggestions)
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
            if (currentRoom.hasQuizzes)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  spacing: SoliplexSpacing.s2,
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
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: SoliplexSpacing.s2,
                      runSpacing: SoliplexSpacing.s2,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final entry in currentRoom.quizzes.entries)
                          if (onQuizTapped != null)
                            SoliplexChip.action(
                              icon: const Icon(Icons.play_arrow),
                              label: Text(entry.value),
                              onPressed: () => onQuizTapped!(entry.key),
                            )
                          else
                            SoliplexChip(
                              icon: const Icon(Icons.play_arrow),
                              label: Text(entry.value),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
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
          borderRadius: BorderRadius.circular(context.radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(context.radii.md),
            ),
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
        ),
      ),
    );
  }
}
