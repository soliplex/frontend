import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Shows a modal yes/no confirmation and resolves to the user's choice.
///
/// Returns `true` only when the confirm action is chosen; cancelling or
/// dismissing the barrier resolves to `false`. Set [isDestructive] to paint
/// the confirm action with the error palette for removals and deletions.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        SoliplexButton.text(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        SoliplexButton.text(
          onPressed: () => Navigator.pop(dialogContext, true),
          intent: isDestructive ? ButtonIntent.danger : ButtonIntent.primary,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
