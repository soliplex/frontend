import 'package:flutter/material.dart';

class FeedbackReasonDialog extends StatefulWidget {
  const FeedbackReasonDialog({super.key});

  @override
  State<FeedbackReasonDialog> createState() => _FeedbackReasonDialogState();
}

class _FeedbackReasonDialogState extends State<FeedbackReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tell us why'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        decoration: const InputDecoration(hintText: 'Add a reason (optional)'),
        textInputAction: TextInputAction.newline,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
