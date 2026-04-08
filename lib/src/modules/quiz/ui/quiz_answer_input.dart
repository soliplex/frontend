import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart';

import '../quiz_session.dart';

class QuizMultipleChoiceInput extends StatelessWidget {
  const QuizMultipleChoiceInput({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.questionState,
    required this.onSelected,
  });

  final List<String> options;
  final String? selectedOption;
  final QuestionState questionState;
  final void Function(String option) onSelected;

  @override
  Widget build(BuildContext context) {
    final isDisabled = questionState is Answered || questionState is Submitting;
    final answeredResult = switch (questionState) {
      Answered(:final result) => result,
      _ => null,
    };
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        for (final option in options)
          _OptionTile(
            option: option,
            isSelected: selectedOption == option,
            isDisabled: isDisabled,
            answeredResult: answeredResult,
            colorScheme: colorScheme,
            onTap: isDisabled ? null : () => onSelected(option),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.isSelected,
    required this.isDisabled,
    required this.answeredResult,
    required this.colorScheme,
    this.onTap,
  });

  final String option;
  final bool isSelected;
  final bool isDisabled;
  final QuizAnswerResult? answeredResult;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isCorrect = switch (answeredResult) {
      CorrectAnswer() => isSelected,
      IncorrectAnswer(:final expectedAnswer) =>
        expectedAnswer.trim().toLowerCase() == option.trim().toLowerCase(),
      _ => false,
    };
    final isWrong =
        answeredResult != null && isSelected && !answeredResult!.isCorrect;

    final backgroundColor = switch ((isCorrect, isWrong, isSelected)) {
      (true, _, _) => colorScheme.primaryContainer,
      (_, true, _) => colorScheme.errorContainer,
      (_, _, true) => colorScheme.secondaryContainer,
      _ => colorScheme.surface,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? colorScheme.primary : colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isDisabled
                      ? colorScheme.onSurface.withValues(alpha: 0.38)
                      : isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                ),
                Expanded(child: Text(option)),
                if (isCorrect)
                  Icon(Icons.check_circle, color: colorScheme.primary),
                if (isWrong) Icon(Icons.cancel, color: colorScheme.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuizTextInput extends StatelessWidget {
  const QuizTextInput({
    super.key,
    required this.controller,
    required this.questionState,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final QuestionState questionState;
  final void Function(String text) onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final isDisabled = questionState is Answered || questionState is Submitting;

    return TextField(
      controller: controller,
      enabled: !isDisabled,
      textInputAction: TextInputAction.done,
      onSubmitted: isDisabled ? null : (_) => onSubmitted(),
      onChanged: onChanged,
      decoration: const InputDecoration(
        hintText: 'Type your answer...',
        border: OutlineInputBorder(),
      ),
    );
  }
}
