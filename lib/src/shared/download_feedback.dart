import 'package:flutter/material.dart';

/// Result of a file download attempt.
sealed class DownloadOutcome {}

/// Where a file's download stands. An outcome that shows, [DownloadSaved] or
/// [DownloadFailed], is a state as it is.
sealed class DownloadFeedbackState {}

/// No download runs, and no outcome shows.
final class DownloadIdle implements DownloadFeedbackState {
  const DownloadIdle();
}

final class DownloadRunning implements DownloadFeedbackState {
  const DownloadRunning();
}

/// The file was saved, or on the web handed to the browser.
final class DownloadSaved implements DownloadOutcome, DownloadFeedbackState {
  const DownloadSaved();
}

/// Nothing was saved and nothing failed: the user cancelled the save, or
/// nobody was left to want the file. Kept apart from [DownloadFailed] so
/// the UI shows no error for it.
final class DownloadCancelled implements DownloadOutcome {
  const DownloadCancelled();
}

final class DownloadFailed implements DownloadOutcome, DownloadFeedbackState {
  const DownloadFailed(this.reason);

  /// Why, in words for the user: fixed text, never the error's own.
  final String reason;
}

/// Shared icon, label and color for each [DownloadFeedbackState]. An icon
/// action (a file row's, a viewer's title bar's) uses [affordance] as it
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

  /// Whether a download may start: none runs, and no save shows. A failed
  /// one may, as a retry.
  bool get canStart => switch (this) {
        DownloadIdle() || DownloadFailed() => true,
        DownloadRunning() || DownloadSaved() => false,
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
