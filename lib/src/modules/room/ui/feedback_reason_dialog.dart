import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
      content: SoliplexInput(
        controller: _controller,
        autofocus: true,
        maxLines: 5,
        hintText: 'Add a reason (optional)',
        textInputAction: TextInputAction.newline,
      ),
      actions: [
        SoliplexButton.text(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        SoliplexButton.filled(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
