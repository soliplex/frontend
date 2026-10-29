import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'download_outcome.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.download_feedback');

/// What a download affordance shows: ready, under way, then the outcome for
/// a moment before it is ready again. A save the user cancels
/// ([DownloadOutcome.cancelled]) goes straight back to [idle].
enum DownloadFeedbackState { idle, downloading, success, error }

/// Shared icon + label for each [DownloadFeedbackState]. Every download
/// affordance (file row tooltip, fallback button labels) renders the
/// same words and, where an icon shows, the same icon; centralizing the
/// mapping here keeps them from drifting apart.
extension DownloadFeedbackAffordance on DownloadFeedbackState {
  (IconData icon, String label) get affordance => switch (this) {
        DownloadFeedbackState.idle => (Icons.download_outlined, 'Download'),
        DownloadFeedbackState.downloading => (
            Icons.download_outlined,
            'Downloading'
          ),
        DownloadFeedbackState.success => (Icons.check, 'Saved'),
        DownloadFeedbackState.error => (Icons.error_outline, "Couldn't save"),
      };

  /// [affordance] for a button, which shows a download under way by loading:
  /// it keeps the idle words, hidden, so it keeps its size while its spinner
  /// says what is happening.
  (IconData icon, String label) get buttonAffordance =>
      (this == DownloadFeedbackState.downloading
              ? DownloadFeedbackState.idle
              : this)
          .affordance;
}

/// Owns the download-feedback state machine so every download affordance
/// (file row, can't-preview fallback, too-large fallback) gets the same
/// behavior: tap → downloading → success or error for 2 s → idle.
///
/// The visual is supplied by [builder]; this widget only orchestrates
/// the state. [onTap] is null in every state but
/// [DownloadFeedbackState.idle], so this affordance starts no second download
/// while one runs or its outcome shows.
class DownloadFeedbackButton extends StatefulWidget {
  const DownloadFeedbackButton({
    super.key,
    required this.filename,
    required this.onDownload,
    required this.builder,
    this.extraLogAttributes = const <String, Object>{},
    this.logTag = 'download callback threw',
  });

  final String filename;

  /// Must convert routine IO failures into [DownloadOutcome.failed]
  /// rather than throw. A throw is treated as a contract violation and
  /// logged at error level.
  final Future<DownloadOutcome> Function() onDownload;

  final Map<String, Object> extraLogAttributes;

  /// Short identifier used as the log message when [onDownload] throws.
  /// Helps grep failures back to a specific call site.
  final String logTag;

  final Widget Function(
    BuildContext context,
    DownloadFeedbackState state,
    VoidCallback? onTap,
  ) builder;

  @override
  State<DownloadFeedbackButton> createState() => _DownloadFeedbackButtonState();
}

class _DownloadFeedbackButtonState extends State<DownloadFeedbackButton> {
  DownloadFeedbackState _state = DownloadFeedbackState.idle;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_state != DownloadFeedbackState.idle) return;
    setState(() => _state = DownloadFeedbackState.downloading);
    DownloadOutcome outcome;
    try {
      outcome = await widget.onDownload();
    } catch (error, stack) {
      // Contract violation per [onDownload]'s doc. Tag the runtime
      // type so unexpected throws are grep-distinguishable in logs.
      _logger.error(
        widget.logTag,
        error: error,
        stackTrace: stack,
        attributes: {
          'filename': widget.filename,
          'errorType': error.runtimeType.toString(),
          ...widget.extraLogAttributes,
        },
      );
      outcome = DownloadOutcome.failed;
    }
    if (!mounted) return;
    if (outcome == DownloadOutcome.cancelled) {
      setState(() => _state = DownloadFeedbackState.idle);
      return;
    }
    setState(() {
      _state = outcome == DownloadOutcome.success
          ? DownloadFeedbackState.success
          : DownloadFeedbackState.error;
    });
    _revertTimer?.cancel();
    _revertTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _state = DownloadFeedbackState.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onTap = _state == DownloadFeedbackState.idle ? _handleTap : null;
    return widget.builder(context, _state, onTap);
  }
}
