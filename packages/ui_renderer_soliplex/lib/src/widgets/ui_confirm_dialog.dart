import 'package:flutter/material.dart';

class UiConfirmDialog extends StatelessWidget {
  const UiConfirmDialog({
    super.key,
    required this.verb,
    required this.message,
    this.target,
  });

  final String verb;
  final String message;
  final String? target;

  static Future<bool> show({
    required BuildContext context,
    required String verb,
    required String message,
    String? target,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          UiConfirmDialog(verb: verb, message: message, target: target),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDestructive =
        const {'delete', 'clear', 'reset', 'remove'}.contains(verb);

    return AlertDialog(
      title: Text(_capitalize(verb)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (target != null) ...[
            const SizedBox(height: 8),
            Text(
              target!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: isDestructive
              ? TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                )
              : null,
          child: Text(_capitalize(verb)),
        ),
      ],
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
