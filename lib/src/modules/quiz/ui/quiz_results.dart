import 'package:flutter/material.dart';

import '../quiz_session.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
      >= 70 => (theme.colorScheme.success, Icons.emoji_events),
      >= 40 => (theme.colorScheme.warning, Icons.thumb_up),
      _ => (theme.colorScheme.danger, Icons.refresh),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
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
                spacing: SoliplexSpacing.s2,
                runSpacing: SoliplexSpacing.s2,
                children: [
                  SoliplexButton.outlined(
                    onPressed: onBack,
                    child: const Text('Back to Room'),
                  ),
                  SoliplexButton.filled(
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
