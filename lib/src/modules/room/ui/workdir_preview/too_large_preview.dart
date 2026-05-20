import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../workdir_files_section.dart' show DownloadOutcome;

/// Rendered when the fetched bytes exceed the preview size cap. Mirrors
/// the inline download-feedback pattern used elsewhere (icon swaps, no
/// SnackBars) so the cap doesn't introduce a one-off UI affordance.
class TooLargePreview extends StatefulWidget {
  const TooLargePreview({
    super.key,
    required this.byteSize,
    required this.capBytes,
    required this.onDownload,
  });

  final int byteSize;
  final int capBytes;
  final Future<DownloadOutcome> Function() onDownload;

  @override
  State<TooLargePreview> createState() => _TooLargePreviewState();
}

enum _Feedback { idle, success, error }

class _TooLargePreviewState extends State<TooLargePreview> {
  _Feedback _feedback = _Feedback.idle;
  bool _inFlight = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleDownload() async {
    if (_inFlight) return;
    _inFlight = true;
    DownloadOutcome outcome;
    try {
      outcome = await widget.onDownload();
    } catch (_) {
      outcome = DownloadOutcome.failed;
    } finally {
      _inFlight = false;
    }
    if (!mounted) return;
    if (outcome == DownloadOutcome.cancelled) return;
    setState(() {
      _feedback = outcome == DownloadOutcome.success
          ? _Feedback.success
          : _Feedback.error;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _feedback = _Feedback.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (_feedback) {
      _Feedback.idle => (Icons.download_outlined, 'Download'),
      _Feedback.success => (Icons.check, 'Saved'),
      _Feedback.error => (Icons.error_outline, "Couldn't save"),
    };
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
            '${_formatBytes(widget.byteSize)} — cap '
            '${_formatBytes(widget.capBytes)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          FilledButton.icon(
            onPressed: _feedback == _Feedback.idle ? _handleDownload : null,
            icon: Icon(icon),
            label: Text(label),
          ),
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
