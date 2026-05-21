import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import 'download_feedback_button.dart';
import 'download_outcome.dart';

/// Rendered when the fetched bytes exceed the preview size cap. Mirrors
/// the inline download-feedback pattern used elsewhere (icon swaps, no
/// SnackBars) so the cap doesn't introduce a one-off UI affordance.
class TooLargePreview extends StatelessWidget {
  const TooLargePreview({
    super.key,
    required this.filename,
    required this.byteSize,
    required this.capBytes,
    required this.onDownload,
  });

  final String filename;
  final int byteSize;
  final int capBytes;
  final Future<DownloadOutcome> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.scale_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'File is too large to preview',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            '${_formatBytes(byteSize)} — cap ${_formatBytes(capBytes)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          DownloadFeedbackButton(
            filename: filename,
            onDownload: onDownload,
            logTag: 'too-large download callback threw',
            extraLogAttributes: {'byteSize': byteSize},
            builder: (context, state, onTap) {
              final (icon, label) = _affordanceFor(state);
              return FilledButton.icon(
                onPressed: onTap,
                icon: Icon(icon),
                label: Text(label),
              );
            },
          ),
        ],
      ),
    );
  }
}

(IconData, String) _affordanceFor(DownloadFeedbackState state) =>
    switch (state) {
      DownloadFeedbackState.idle => (Icons.download_outlined, 'Download'),
      DownloadFeedbackState.success => (Icons.check, 'Saved'),
      DownloadFeedbackState.error => (Icons.error_outline, "Couldn't save"),
    };

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
