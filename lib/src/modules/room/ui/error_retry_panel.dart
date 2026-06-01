import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show AuthException;
import 'package:soliplex_design/soliplex_design.dart';

class ErrorRetryPanel extends StatelessWidget {
  const ErrorRetryPanel({
    super.key,
    required this.title,
    required this.error,
    this.onRetry,
    this.onReauthenticate,
  });

  final String title;
  final Object error;
  final VoidCallback? onRetry;

  /// Re-authentication action shown instead of retry when [error] is an
  /// [AuthException]. Retrying a request with a dead or missing token just
  /// round-trips the same 401, so the user needs to sign in again.
  final VoidCallback? onReauthenticate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showReauth = error is AuthException && onReauthenticate != null;
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
          if (showReauth)
            SoliplexButton.filled(
              onPressed: onReauthenticate,
              child: const Text('Sign in'),
            )
          else if (onRetry != null)
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
