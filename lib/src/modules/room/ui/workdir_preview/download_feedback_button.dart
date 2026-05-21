import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'download_outcome.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.download_feedback');

/// Three-state download feedback the user sees after tapping a download
/// affordance. [DownloadOutcome.cancelled] never reaches the builder —
/// it leaves the state at [idle] and never animates.
enum DownloadFeedbackState { idle, success, error }

/// Owns the download-feedback state machine so every download affordance
/// (file row, can't-preview fallback, too-large fallback) gets the same
/// behavior: tap → in-flight guard → success/error swap → 2 s revert.
///
/// The visual is supplied by [builder]; this widget only orchestrates
/// the state. [onTap] is null while in-flight, when feedback is showing,
/// or when the host wants the affordance disabled.
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
  /// logged at error level (see [_handleTap]).
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
  bool _inFlight = false;
  Timer? _revertTimer;

  @override
  void dispose() {
    _revertTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_inFlight) return;
    setState(() => _inFlight = true);
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
      setState(() => _inFlight = false);
      return;
    }
    setState(() {
      _inFlight = false;
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
    final onTap = (!_inFlight && _state == DownloadFeedbackState.idle)
        ? _handleTap
        : null;
    return widget.builder(context, _state, onTap);
  }
}
