import 'package:flutter/material.dart';

import '../../../../soliplex_frontend.dart';
import '../quiz_session.dart';

class QuizResultsView extends StatelessWidget {
  const QuizResultsView({
    super.key,
    required this.session,
    required this.onBack,
    required this.onRetake,
  });

  final QuizCompleted session;
  final VoidCallback onBack;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = session.scorePercent;

    final (scoreColor, scoreIcon) = switch (percent) {
      >= 70 => (theme.colorScheme.primary, Icons.emoji_events),
      >= 40 => (theme.colorScheme.tertiary, Icons.thumb_up),
      _ => (theme.colorScheme.error, Icons.refresh),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(scoreIcon, size: 64, color: scoreColor),
              const SizedBox(height: SoliplexSpacing.s4),
              Text('Quiz Complete!', style: theme.textTheme.headlineMedium),
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                '${session.scorePercent}%',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                '${session.correctCount} of ${session.totalAnswered} correct',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onBack,
                    child: const Text('Back to Room'),
                  ),
                  FilledButton(
                    onPressed: onRetake,
                    child: const Text('Retake Quiz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
