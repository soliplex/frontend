import 'package:flutter/material.dart';

import '../../file_downloads.dart';

/// Shared icon, label and color for each [DownloadFeedbackState]. An icon
/// action (a file row's, the preview title bar's) uses [affordance] as it
/// is; a labelled button uses [buttonAffordance], which differs while
/// downloading and on a failure. Centralizing the mapping here keeps the
/// affordances from drifting apart.
extension DownloadFeedbackAffordance on DownloadFeedbackState {
  /// An icon action's icon and tooltip: a failure's says why, and that a
  /// tap retries.
  (IconData icon, String label) get affordance => switch (this) {
        DownloadIdle() => (Icons.download_outlined, 'Download'),
        DownloadRunning() => (Icons.download_outlined, 'Downloading'),
        DownloadSaved() => (Icons.check, 'Saved'),
        DownloadFailed(:final reason) => (
            Icons.error_outline,
            'Download failed: $reason. Tap to retry.'
          ),
      };

  /// The color an outcome shows in, or null before there is one.
  Color? outcomeColor(ColorScheme colors) => switch (this) {
        DownloadIdle() || DownloadRunning() => null,
        DownloadSaved() => colors.onSurfaceVariant,
        DownloadFailed() => colors.error,
      };

  /// [affordance] for a button, which shows a download under way by loading:
  /// it keeps the idle words, hidden, so it keeps its size. Only its spinner
  /// shows the download is under way; a screen reader hears the idle words on
  /// a disabled button. A failure's label offers the retry a tap makes, and
  /// leaves out its reason, which the button's page shows under it.
  (IconData icon, String label) get buttonAffordance => switch (this) {
        DownloadRunning() => const DownloadIdle().affordance,
        DownloadFailed() => (Icons.error_outline, 'Retry download'),
        DownloadIdle() || DownloadSaved() => affordance,
      };
}
