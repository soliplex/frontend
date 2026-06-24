import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

class QuizAnswerFeedback extends StatelessWidget {
  const QuizAnswerFeedback({super.key, required this.result});
  final QuizAnswerResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCorrect = result.isCorrect;

    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      decoration: BoxDecoration(
        color: isCorrect
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.cancel,
            color: isCorrect ? context.success : colorScheme.error,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCorrect ? 'Correct!' : 'Incorrect',
                  style: textTheme.titleMedium?.copyWith(
                    color: isCorrect
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onErrorContainer,
                  ),
                ),
                if (result case IncorrectAnswer(:final expectedAnswer)) ...[
                  const SizedBox(height: SoliplexSpacing.s1),
                  Text(
                    'Expected: $expectedAnswer',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuizErrorFeedback extends StatelessWidget {
  const QuizErrorFeedback({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          SoliplexButton.text(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
