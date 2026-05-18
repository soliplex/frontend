import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../../../../soliplex_frontend.dart';
import '../quiz_session.dart';
import 'quiz_answer_input.dart';
import 'quiz_feedback.dart';

class QuizQuestionView extends StatelessWidget {
  const QuizQuestionView({
    super.key,
    required this.session,
    required this.answerController,
    required this.submissionError,
    required this.onSelectOption,
    required this.onTextChanged,
    required this.onSubmit,
    required this.onNext,
    required this.onRetry,
  });

  final QuizInProgress session;
  final TextEditingController answerController;
  final String? submissionError;
  final void Function(String option) onSelectOption;
  final void Function(String text) onTextChanged;
  final VoidCallback onSubmit;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final question = session.currentQuestion;
    final questionState = session.questionState;
    final theme = Theme.of(context);

    final selectedOption = switch (questionState) {
      Composing(input: MultipleChoiceInput(:final selectedOption)) =>
        selectedOption,
      Submitting(input: MultipleChoiceInput(:final selectedOption)) =>
        selectedOption,
      Answered(input: MultipleChoiceInput(:final selectedOption)) =>
        selectedOption,
      _ => null,
    };

    return Column(
      children: [
        LinearProgressIndicator(
          value: session.progress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Question ${session.currentIndex + 1} of '
                      '${session.quiz.questionCount}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: SoliplexSpacing.s2),
                    Text(question.text, style: theme.textTheme.titleLarge),
                    const SizedBox(height: SoliplexSpacing.s4),
                    _buildInput(question, questionState, selectedOption),
                    if (submissionError != null) ...[
                      const SizedBox(height: SoliplexSpacing.s4),
                      QuizErrorFeedback(
                        message: submissionError!,
                        onRetry: onRetry,
                      ),
                    ],
                    if (questionState case Answered(:final result)) ...[
                      const SizedBox(height: SoliplexSpacing.s4),
                      QuizAnswerFeedback(result: result),
                    ],
                    const SizedBox(height: SoliplexSpacing.s4),
                    _buildActionButton(questionState),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
    QuizQuestion question,
    QuestionState questionState,
    String? selectedOption,
  ) {
    return switch (question.type) {
      MultipleChoice(:final options) => QuizMultipleChoiceInput(
          options: options,
          selectedOption: selectedOption,
          questionState: questionState,
          onSelected: onSelectOption,
        ),
      FillBlank() || FreeForm() => QuizTextInput(
          controller: answerController,
          questionState: questionState,
          onChanged: onTextChanged,
          onSubmitted: onSubmit,
        ),
    };
  }

  Widget _buildActionButton(QuestionState questionState) {
    return switch (questionState) {
      AwaitingInput() => const FilledButton(
          onPressed: null,
          child: Text('Submit Answer'),
        ),
      Composing(:final canSubmit) => FilledButton(
          onPressed: canSubmit ? onSubmit : null,
          child: const Text('Submit Answer'),
        ),
      Submitting() => const FilledButton(
          onPressed: null,
          child: SizedBox(
            width: SoliplexSpacing.s5,
            height: SoliplexSpacing.s5,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      Answered() => FilledButton(
          onPressed: onNext,
          child: Text(
            session.isLastQuestion ? 'See Results' : 'Next Question',
          ),
        ),
    };
  }
}
