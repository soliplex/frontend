import 'package:flutter/material.dart';

class UiModalDialog extends StatelessWidget {
  const UiModalDialog({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final String title;
  final String body;
  final List<String> actions;

  static Future<String?> show({
    required BuildContext context,
    required String title,
    required String body,
    List<String>? actions,
  }) {
    final effectiveActions =
        (actions == null || actions.isEmpty) ? ['Dismiss'] : actions;
    return showDialog<String>(
      context: context,
      builder: (_) => UiModalDialog(
        title: title,
        body: body,
        actions: effectiveActions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: actions
          .map(
            (label) => TextButton(
              onPressed: () => Navigator.of(context).pop(label),
              child: Text(label),
            ),
          )
          .toList(),
    );
  }
}
