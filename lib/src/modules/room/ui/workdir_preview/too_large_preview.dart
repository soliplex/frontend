import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Rendered when the fetched bytes exceed the preview size cap: says so, and
/// offers [downloadButton].
class TooLargePreview extends StatelessWidget {
  const TooLargePreview({
    super.key,
    required this.byteSize,
    required this.capBytes,
    required this.downloadButton,
  });

  final int byteSize;
  final int capBytes;

  /// The file's Download button.
  final Widget downloadButton;

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
          downloadButton,
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
