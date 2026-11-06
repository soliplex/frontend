import 'package:flutter/material.dart';

import '../../file_downloads.dart';

/// Shared icon, label and color for each [DownloadFeedbackState]. An icon
/// action (a file row's, the preview title bar's) uses [affordance] as it
/// is; a labelled button uses [buttonAffordance], which differs only while
/// downloading. Centralizing the mapping here keeps the affordances from
/// drifting apart.
extension DownloadFeedbackAffordance on DownloadFeedbackState {
  (IconData icon, String label) get affordance => switch (this) {
        DownloadFeedbackState.idle => (Icons.download_outlined, 'Download'),
        DownloadFeedbackState.downloading => (
            Icons.download_outlined,
            'Downloading'
          ),
        DownloadFeedbackState.success => (Icons.check, 'Saved'),
        DownloadFeedbackState.error => (Icons.error_outline, 'Download failed'),
      };

  /// The color an outcome shows in, or null before there is one.
  Color? outcomeColor(ColorScheme colors) => switch (this) {
        DownloadFeedbackState.idle || DownloadFeedbackState.downloading => null,
        DownloadFeedbackState.success => colors.onSurfaceVariant,
        DownloadFeedbackState.error => colors.error,
      };

  /// [affordance] for a button, which shows a download under way by loading:
  /// it keeps the idle words, hidden, so it keeps its size. Only its spinner
  /// shows the download is under way; a screen reader hears the idle words on
  /// a disabled button.
  (IconData icon, String label) get buttonAffordance =>
      (this == DownloadFeedbackState.downloading
              ? DownloadFeedbackState.idle
              : this)
          .affordance;
}
