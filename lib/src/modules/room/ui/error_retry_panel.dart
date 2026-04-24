import 'package:flutter/material.dart';
import '../../../../soliplex_frontend.dart';

class ErrorRetryPanel extends StatelessWidget {
  const ErrorRetryPanel({
    super.key,
    required this.title,
    required this.error,
    this.onRetry,
  });

  final String title;
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.bodyMedium),
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          if (onRetry != null)
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
