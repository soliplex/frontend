import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

class QuizStartView extends StatelessWidget {
  const QuizStartView({
    super.key,
    required this.quiz,
    required this.onStart,
  });

  final Quiz quiz;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: SoliplexSpacing.s4),
              Text(
                quiz.title,
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                quiz.questionCount == 1
                    ? '1 question'
                    : '${quiz.questionCount} questions',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s6),
              SoliplexButton.filled(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                child: const Text('Start Quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
