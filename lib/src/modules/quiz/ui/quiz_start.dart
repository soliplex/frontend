import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

class QuizStartView extends StatelessWidget {
  const QuizStartView({super.key, required this.quiz, required this.onStart});

  final Quiz quiz;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                quiz.title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                quiz.questionCount == 1
                    ? '1 question'
                    : '${quiz.questionCount} questions',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
