import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.downloads');

/// Result of a workdir-file download attempt. [cancelled] saved nothing
/// and nothing failed: the user cancelled the save, or nobody was left to
/// want the file. It is kept apart from [failed] so the UI shows no error
/// for it.
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
  /// [DownloadOutcome.failed] rather than throw. Its `isCleared` says whether
  /// these downloads were cleared since, so nobody is left to want the file.
  final Future<DownloadOutcome> Function(
    WorkdirFile file,
    bool Function() isCleared,
  ) _download;

  /// The files not idle, by path, so a file absent from it is idle. A path,
  /// not the listed [WorkdirFile], so a refresh that reports the file with a
  /// new modified time or size leaves its download in place.
  final _states = Signal<Map<String, DownloadFeedbackState>>(const {});
  final _outcomeTimers = <String, Timer>{};
  bool _isDisposed = false;

  /// [file]'s state; read inside a `Watch`, it rebuilds when any file's
  /// download changes.
  DownloadFeedbackState stateOf(WorkdirFile file) =>
      _states.value[file.filename] ?? DownloadFeedbackState.idle;

  /// Downloads [file], unless its download runs or its outcome shows.
  /// Starts nothing once disposed, when nobody is left to want the file.
  Future<void> start(WorkdirFile file) async {
    if (_isDisposed) {
      _logger.debug(
        'download not started, its downloads cleared',
        attributes: {'filename': file.filename},
      );
      return;
    }
    if (stateOf(file) != DownloadFeedbackState.idle) return;
    final path = file.filename;
    _set(path, DownloadFeedbackState.downloading);
    DownloadOutcome outcome;
    try {
      outcome = await _download(file, () => _isDisposed);
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
    // The outcome is logged; nothing is left to show it.
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

  /// Clears these downloads: every file reads idle and none starts again.
  /// The state stays readable, not disposed, as a screen that still shows
  /// these downloads may read it until it is rebuilt or goes away.
  void dispose() {
    _isDisposed = true;
    for (final timer in _outcomeTimers.values) {
      timer.cancel();
    }
    _states.value = const {};
  }
}
