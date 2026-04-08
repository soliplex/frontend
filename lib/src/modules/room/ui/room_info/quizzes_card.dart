import 'package:flutter/material.dart';

import 'room_info_widgets.dart';

class QuizzesCard extends StatelessWidget {
  const QuizzesCard({
    super.key,
    required this.quizzes,
    required this.onQuizTapped,
  });

  final Map<String, String> quizzes;
  final void Function(String quizId)? onQuizTapped;

  @override
  Widget build(BuildContext context) {
    final title = quizzes.isEmpty ? 'QUIZZES' : 'QUIZZES (${quizzes.length})';

    return SectionCard(
      title: title,
      children: [
        if (quizzes.isEmpty)
          const EmptyMessage(label: 'quizzes')
        else
          for (final entry in quizzes.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.quiz, size: 20),
              title: Text(entry.value),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap:
                  onQuizTapped != null ? () => onQuizTapped!(entry.key) : null,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
      ],
    );
  }
}
