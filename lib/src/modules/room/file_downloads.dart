import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.downloads');

/// Result of a workdir-file download attempt. Distinguishes user-
/// initiated cancellation from real failure so the UI can render the
/// right inline feedback.
enum DownloadOutcome { success, cancelled, failed }

/// Where a file's download stands in [FileDownloads].
enum DownloadFeedbackState { idle, downloading, success, error }

/// Each file's download in one thread's workspace: idle, under way, then its
/// outcome for 2 s before it is idle again. A save the user cancels goes
/// straight back to idle.
///
/// Every affordance that downloads a file reads its state here and starts it
/// here, so a file row and the preview show one download, and a file starts
/// no second one while one runs or its outcome shows.
class FileDownloads {
  FileDownloads(this._download);

  /// Downloads a file; must report routine failures as
  /// [DownloadOutcome.failed] rather than throw.
  final Future<DownloadOutcome> Function(WorkdirFile file) _download;

  /// The files not idle, by path, so a file absent from it is idle. A path,
  /// not the listed [WorkdirFile], so a refresh that reports the file with a
  /// new modified time or size leaves its download in place.
  final _states = Signal<Map<String, DownloadFeedbackState>>(const {});
  final _outcomeTimers = <String, Timer>{};
  bool _isDisposed = false;

  /// Whether these downloads were cleared, so none of them shows any more.
  bool get isDisposed => _isDisposed;

  /// [file]'s state; read inside a `Watch`, it rebuilds when that changes.
  DownloadFeedbackState stateOf(WorkdirFile file) =>
      _states.value[file.filename] ?? DownloadFeedbackState.idle;

  /// Downloads [file], unless its download runs or its outcome shows.
  /// Does nothing once disposed, when nothing is left to show it.
  Future<void> start(WorkdirFile file) async {
    if (_isDisposed || stateOf(file) != DownloadFeedbackState.idle) return;
    final path = file.filename;
    _set(path, DownloadFeedbackState.downloading);
    DownloadOutcome outcome;
    try {
      outcome = await _download(file);
    } catch (e, st) {
      // A broken contract, so it may carry anything: its text stays out.
      _logger.error(
        'workdir download threw',
        stackTrace: st,
        attributes: {
          'filename': path,
          'failure': describeFailure(e),
        },
      );
      outcome = DownloadOutcome.failed;
    }
    // [_download] has logged the outcome; nothing is left to show it.
    if (_isDisposed) return;
    switch (outcome) {
      case DownloadOutcome.cancelled:
        _set(path, DownloadFeedbackState.idle);
      case DownloadOutcome.success:
        _showOutcome(path, DownloadFeedbackState.success);
      case DownloadOutcome.failed:
        _showOutcome(path, DownloadFeedbackState.error);
    }
  }

  void _showOutcome(String path, DownloadFeedbackState outcome) {
    _set(path, outcome);
    _outcomeTimers[path] = Timer(const Duration(seconds: 2), () {
      _outcomeTimers.remove(path);
      _set(path, DownloadFeedbackState.idle);
    });
  }

  void _set(String path, DownloadFeedbackState state) {
    _states.value = state == DownloadFeedbackState.idle
        ? ({..._states.value}..remove(path))
        : {..._states.value, path: state};
  }

  void dispose() {
    _isDisposed = true;
    for (final timer in _outcomeTimers.values) {
      timer.cancel();
    }
    _states.dispose();
  }
}
